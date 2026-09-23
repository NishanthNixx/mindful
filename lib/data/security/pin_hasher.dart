import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 for the app-lock PIN. Encoded as
/// `pbkdf2-sha256$<iterations>$<saltHex>$<hashHex>` so parameters can be raised
/// later without breaking existing PINs.
class PinHasher {
  const PinHasher({this.iterations = 120000, this.useIsolate = true});

  final int iterations;

  /// Off only in tests, where background isolates don't run under fake time.
  final bool useIsolate;

  Future<T> _run<T>(T Function() work) =>
      useIsolate ? Isolate.run(work) : Future.value(work());

  static const _prefix = 'pbkdf2-sha256';

  Future<String> hash(String pin, {Random? random}) {
    final rng = random ?? Random.secure();
    final salt = Uint8List.fromList([
      for (var i = 0; i < 16; i++) rng.nextInt(256),
    ]);
    final iters = iterations;
    return _run(() {
      final dk = _pbkdf2(utf8.encode(pin), salt, iters);
      return '$_prefix\$$iters\$${_hex(salt)}\$${_hex(dk)}';
    });
  }

  Future<bool> verify(String pin, String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != _prefix) return Future.value(false);
    final iters = int.parse(parts[1]);
    final salt = _unhex(parts[2]);
    final expected = _unhex(parts[3]);
    return _run(
      () =>
          _constantTimeEquals(_pbkdf2(utf8.encode(pin), salt, iters), expected),
    );
  }

  /// Single-block PBKDF2 (32-byte output == one SHA-256 block).
  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, password);
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String s) => Uint8List.fromList([
    for (var i = 0; i < s.length; i += 2)
      int.parse(s.substring(i, i + 2), radix: 16),
  ]);
}
