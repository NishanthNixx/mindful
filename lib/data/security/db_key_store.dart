import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owns the database encryption key. The key is generated on first launch
/// with a CSPRNG and lives only in the platform keystore.
class DbKeyStore {
  DbKeyStore(this._storage, {Random? random})
    : _random = random ?? Random.secure();

  static const _keyName = 'db_key_v1';

  final FlutterSecureStorage _storage;
  final Random _random;

  Future<String> getOrCreateKey() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null) return existing;
    final key = [
      for (var i = 0; i < 32; i++)
        _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    await _storage.write(key: _keyName, value: key);
    return key;
  }

  /// Crypto-shred: once the key is gone the database file is unreadable.
  Future<void> destroyKey() => _storage.delete(key: _keyName);
}
