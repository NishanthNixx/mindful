import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  final int receivedBytes;
  final int totalBytes;
  final double bytesPerSecond;
}

class DownloadException implements Exception {
  const DownloadException(this.message, {this.retryable = true});

  final String message;

  /// False for problems a retry won't fix (e.g. 404, access denied).
  final bool retryable;

  @override
  String toString() => 'DownloadException: $message';
}

/// Resumable HTTP download into a `.part` file using `Range` requests, so it
/// survives pauses, network drops and the app being killed: the next call
/// continues from the bytes already on disk.
class ModelDownloader {
  ModelDownloader({
    HttpClient Function()? clientFactory,
    this.stallTimeout = const Duration(seconds: 45),
    this.progressInterval = const Duration(milliseconds: 250),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  final Duration stallTimeout;
  final Duration progressInterval;

  static const _maxRedirects = 8;

  /// Emits progress and completes when [partFile] holds [expectedSize] bytes.
  /// Cancelling the subscription aborts the request and keeps the partial
  /// file for a later resume.
  Stream<DownloadProgress> download({
    required Uri url,
    required File partFile,
    required int expectedSize,
  }) {
    late StreamController<DownloadProgress> controller;
    HttpClient? client;
    IOSink? sink;
    StreamSubscription<List<int>>? body;
    var cancelled = false;

    Future<void> cleanUp() async {
      await body?.cancel();
      await sink?.flush();
      await sink?.close();
      sink = null;
      client?.close(force: true);
    }

    Future<void> run() async {
      await partFile.parent.create(recursive: true);
      var received = partFile.existsSync() ? partFile.lengthSync() : 0;
      if (received > expectedSize) {
        // Stale or wrong file; start over.
        await partFile.writeAsBytes(const [], flush: true);
        received = 0;
      }
      if (received == expectedSize) {
        controller.add(
          DownloadProgress(
            receivedBytes: received,
            totalBytes: expectedSize,
            bytesPerSecond: 0,
          ),
        );
        return;
      }

      client = _clientFactory()
        ..connectionTimeout = const Duration(seconds: 30)
        ..idleTimeout = const Duration(seconds: 30);
      final response = await _open(client!, url, from: received);
      if (cancelled) return;

      switch (response.statusCode) {
        case HttpStatus.partialContent:
          break;
        case HttpStatus.ok:
          // Server ignored the Range header: restart from zero.
          received = 0;
          await partFile.writeAsBytes(const [], flush: true);
        case HttpStatus.requestedRangeNotSatisfiable:
          throw const DownloadException(
            'The server rejected the resume point. Cancel and download again.',
          );
        case HttpStatus.unauthorized || HttpStatus.forbidden:
          throw DownloadException(
            'Access denied (${response.statusCode}).',
            retryable: false,
          );
        case HttpStatus.notFound:
          throw const DownloadException(
            'The model file was not found on the server.',
            retryable: false,
          );
        default:
          throw DownloadException('Server error ${response.statusCode}.');
      }

      sink = partFile.openWrite(mode: FileMode.append);
      final done = Completer<void>();
      final watch = Stopwatch()..start();
      var windowStart = received;
      var windowTime = Duration.zero;
      var lastEmit = Duration.zero;
      double speed = 0;
      Timer? stall;

      void armStall() {
        stall?.cancel();
        stall = Timer(stallTimeout, () {
          if (!done.isCompleted) {
            done.completeError(
              const DownloadException('The connection stalled.'),
            );
          }
        });
      }

      armStall();
      body = response.listen(
        (chunk) {
          sink!.add(chunk);
          received += chunk.length;
          armStall();
          final now = watch.elapsed;
          if (now - lastEmit >= progressInterval) {
            final dt = (now - windowTime).inMicroseconds / 1e6;
            if (dt >= 1) {
              final instant = (received - windowStart) / dt;
              speed = speed == 0 ? instant : speed * 0.7 + instant * 0.3;
              windowStart = received;
              windowTime = now;
            }
            lastEmit = now;
            controller.add(
              DownloadProgress(
                receivedBytes: received,
                totalBytes: expectedSize,
                bytesPerSecond: speed,
              ),
            );
          }
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      try {
        await done.future;
      } finally {
        stall?.cancel();
        await sink?.flush();
        await sink?.close();
        sink = null;
      }
      if (cancelled) return;
      if (received != expectedSize) {
        throw DownloadException(
          'Download ended early ($received of $expectedSize bytes).',
        );
      }
      controller.add(
        DownloadProgress(
          receivedBytes: received,
          totalBytes: expectedSize,
          bytesPerSecond: speed,
        ),
      );
    }

    controller = StreamController<DownloadProgress>(
      onListen: () {
        unawaited(
          run()
              .then(
                (_) {},
                onError: (Object e, StackTrace st) {
                  if (cancelled) return;
                  controller.addError(
                    e is DownloadException
                        ? e
                        : e is SocketException ||
                              e is HttpException ||
                              e is TimeoutException
                        ? const DownloadException('The connection was lost.')
                        : e,
                    st,
                  );
                },
              )
              .whenComplete(() async {
                await cleanUp();
                if (!controller.isClosed) await controller.close();
              }),
        );
      },
      onCancel: () async {
        cancelled = true;
        await cleanUp();
      },
    );
    return controller.stream;
  }

  /// GET with Range, following redirects manually so the Range header is
  /// re-sent to the CDN (Hugging Face redirects every file).
  Future<HttpClientResponse> _open(
    HttpClient client,
    Uri url, {
    required int from,
  }) async {
    var target = url;
    for (var i = 0; i < _maxRedirects; i++) {
      final request = await client.getUrl(target);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (from > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      }
      final response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw const DownloadException('Redirect without a location.');
        }
        target = target.resolve(location);
        continue;
      }
      return response;
    }
    throw const DownloadException('Too many redirects.');
  }
}
