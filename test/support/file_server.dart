import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Tiny local HTTP server that behaves like Hugging Face + its CDN:
/// `/redirect` → 302 to `/file`; `/file` honours `Range: bytes=N-`;
/// `/norange` ignores Range; `/half` goes silent halfway; `/slow` streams
/// slowly so a test can pause mid-transfer; `/missing` is 404.
class FileServer {
  FileServer(this.bytes);

  final Uint8List bytes;
  late HttpServer _server;
  final rangeHeaders = <String?>[];

  Uri url(String path) =>
      Uri.parse('http://${_server.address.host}:${_server.port}$path');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    switch (req.uri.path) {
      case '/redirect':
        res
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/file');
        await res.close();
      case '/missing':
        res.statusCode = HttpStatus.notFound;
        await res.close();
      case '/norange':
        rangeHeaders.add(range);
        res.contentLength = bytes.length;
        res.add(bytes);
        await res.close();
      case '/file' || '/half' || '/slow':
        rangeHeaders.add(range);
        final from = range == null
            ? 0
            : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        final body = Uint8List.sublistView(bytes, from);
        res.statusCode = range == null
            ? HttpStatus.ok
            : HttpStatus.partialContent;
        if (range != null) {
          res.headers.set(
            'content-range',
            'bytes $from-${bytes.length - 1}/${bytes.length}',
          );
        }
        res.contentLength = body.length;
        if (req.uri.path == '/half') {
          // Send half, then go silent (a dead connection).
          res.add(Uint8List.sublistView(body, 0, body.length ~/ 2));
          await res.flush();
          await Future<void>.delayed(const Duration(seconds: 20));
          return;
        }
        if (req.uri.path == '/slow') {
          const chunk = 4096;
          for (var i = 0; i < body.length; i += chunk) {
            res.add(
              Uint8List.sublistView(
                body,
                i,
                i + chunk > body.length ? body.length : i + chunk,
              ),
            );
            await res.flush();
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          await res.close();
          return;
        }
        res.add(body);
        await res.close();
      default:
        res.statusCode = HttpStatus.badRequest;
        await res.close();
    }
  }
}

Uint8List testBytes(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + 7) % 256));
