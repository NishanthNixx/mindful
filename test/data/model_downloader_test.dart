import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/data/ai/checksum.dart';
import 'package:mindfull/data/ai/model_downloader.dart';

import '../support/file_server.dart';

void main() {
  final bytes = testBytes(300000);
  late FileServer server;
  late Directory dir;
  late File part;
  final downloader = ModelDownloader(progressInterval: Duration.zero);

  setUp(() async {
    server = FileServer(bytes);
    await server.start();
    dir = Directory.systemTemp.createTempSync('dl_test');
    part = File('${dir.path}/model.bin.part');
  });

  tearDown(() async {
    await server.close();
    dir.deleteSync(recursive: true);
  });

  Future<List<DownloadProgress>> run(String path) => downloader
      .download(
        url: server.url(path),
        partFile: part,
        expectedSize: bytes.length,
      )
      .toList();

  test('downloads through a redirect', () async {
    final progress = await run('/redirect');
    expect(part.readAsBytesSync(), bytes);
    expect(progress.last.receivedBytes, bytes.length);
  });

  test(
    'resumes from the bytes already on disk, re-sending Range after redirect',
    () async {
      part.writeAsBytesSync(bytes.sublist(0, 100000));
      await run('/redirect');
      expect(server.rangeHeaders.single, 'bytes=100000-');
      expect(part.readAsBytesSync(), bytes);
    },
  );

  test('restarts cleanly when the server ignores Range', () async {
    part.writeAsBytesSync(List.filled(500, 0));
    await run('/norange');
    expect(part.readAsBytesSync(), bytes);
  });

  test('already complete file finishes without a request', () async {
    part.writeAsBytesSync(bytes);
    await run('/file');
    expect(server.rangeHeaders, isEmpty);
  });

  test('404 is not retryable', () async {
    await expectLater(
      run('/missing'),
      throwsA(
        isA<DownloadException>().having(
          (e) => e.retryable,
          'retryable',
          isFalse,
        ),
      ),
    );
  });

  test(
    'a stalled connection errors and keeps the partial file for resume',
    () async {
      final impatient = ModelDownloader(
        progressInterval: Duration.zero,
        stallTimeout: const Duration(milliseconds: 300),
      );
      await expectLater(
        impatient
            .download(
              url: server.url('/half'),
              partFile: part,
              expectedSize: bytes.length,
            )
            .toList(),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            contains('stalled'),
          ),
        ),
      );
      final kept = part.lengthSync();
      expect(kept, greaterThan(0));
      expect(kept, lessThan(bytes.length));
      await run('/file');
      expect(server.rangeHeaders.last, 'bytes=$kept-');
      expect(part.readAsBytesSync(), bytes);
    },
  );

  test('cancelling (pause) stops the transfer and keeps bytes', () async {
    final paused = Completer<void>();
    late StreamSubscription<DownloadProgress> sub;
    sub = downloader
        .download(
          url: server.url('/slow'),
          partFile: part,
          expectedSize: bytes.length,
        )
        .listen((p) {
          // Cancel's future completes after the partial file is flushed.
          if (p.receivedBytes > 40000 && !paused.isCompleted) {
            paused.complete(sub.cancel());
          }
        });
    await paused.future;
    final kept = part.lengthSync();
    expect(kept, inExclusiveRange(0, bytes.length));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(part.lengthSync(), kept, reason: 'nothing written after pause');
  });

  test('sha256OfFile matches crypto, on a background isolate', () async {
    part.writeAsBytesSync(bytes);
    final seen = <double>[];
    final digest = await sha256OfFile(part, onProgress: seen.add);
    expect(digest, sha256.convert(bytes).toString());
    expect(seen.last, 1.0);
  });
}
