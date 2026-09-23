import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// SHA-256 of a (multi-GB) file on a background isolate, reporting progress
/// 0..1. Set [useIsolate] to false in tests, where isolates don't run under
/// fake time.
Future<String> sha256OfFile(
  File file, {
  void Function(double progress)? onProgress,
  bool useIsolate = true,
}) async {
  if (!useIsolate) return _hash(file.path, (p) => onProgress?.call(p));

  final port = ReceivePort();
  final result = Completer<String>();
  await Isolate.spawn(
    _entry,
    (file.path, port.sendPort),
    onError: port.sendPort,
    onExit: port.sendPort,
  );
  late StreamSubscription<Object?> sub;
  sub = port.listen((message) {
    switch (message) {
      case final double p:
        onProgress?.call(p);
      case final String digest:
        result.complete(digest);
        unawaited(sub.cancel());
        port.close();
      case [final Object error, _]:
        result.completeError(Exception('Checksum failed: $error'));
        unawaited(sub.cancel());
        port.close();
      case null:
        if (!result.isCompleted) {
          result.completeError(Exception('Checksum isolate exited early'));
        }
        unawaited(sub.cancel());
        port.close();
    }
  });
  return result.future;
}

void _entry((String, SendPort) args) {
  final (path, port) = args;
  port.send(_hash(path, port.send));
}

String _hash(String path, void Function(double) progress) {
  final file = File(path).openSync();
  try {
    final total = file.lengthSync();
    final out = _DigestSink();
    final input = sha256.startChunkedConversion(out);
    const chunk = 8 * 1024 * 1024;
    var read = 0;
    var lastReport = -1.0;
    while (true) {
      final bytes = file.readSync(chunk);
      if (bytes.isEmpty) break;
      input.add(bytes);
      read += bytes.length;
      final p = total == 0 ? 1.0 : read / total;
      if (p - lastReport >= 0.01) {
        progress(p);
        lastReport = p;
      }
    }
    input.close();
    return out.value.toString();
  } finally {
    file.closeSync();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
