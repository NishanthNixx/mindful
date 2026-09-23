import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mindfull/data/security/pin_hasher.dart';

sealed class PinResult {
  const PinResult();
}

class PinAccepted extends PinResult {
  const PinAccepted();
}

class PinRejected extends PinResult {
  const PinRejected({required this.attemptsLeft});

  final int attemptsLeft;
}

class PinLockedOut extends PinResult {
  const PinLockedOut(this.until);

  final DateTime until;
}

/// App lock settings and verification. The PIN hash and failure counter live
/// in the platform keystore, never in the journal database.
class AppLockService {
  AppLockService({
    required FlutterSecureStorage storage,
    LocalAuthentication? localAuth,
    PinHasher hasher = const PinHasher(),
    DateTime Function()? clock,
  }) : _storage = storage,
       _localAuth = localAuth ?? LocalAuthentication(),
       _hasher = hasher,
       _clock = clock ?? DateTime.now;

  static const maxAttempts = 5;
  static const _pinKey = 'lock_pin_hash';
  static const _bioKey = 'lock_biometrics';
  static const _failKey = 'lock_failures';
  static const _lockoutKey = 'lock_lockout_until';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;
  final PinHasher _hasher;
  final DateTime Function() _clock;

  Future<bool> isEnabled() async => await _storage.read(key: _pinKey) != null;

  Future<bool> biometricsEnabled() async =>
      await _storage.read(key: _bioKey) == 'true';

  Future<bool> biometricsAvailable() async {
    try {
      return await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;
    } on Exception {
      // PlatformException, or MissingPluginException where there's no plugin.
      return false;
    }
  }

  Future<void> enable(String pin, {required bool useBiometrics}) async {
    await _storage.write(key: _pinKey, value: await _hasher.hash(pin));
    await _storage.write(key: _bioKey, value: '$useBiometrics');
    await _resetFailures();
  }

  Future<void> setBiometrics({required bool enabled}) =>
      _storage.write(key: _bioKey, value: '$enabled');

  Future<void> disable() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _bioKey);
    await _resetFailures();
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock your journal',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on Exception {
      // Includes LocalAuthException (cancelled, not enrolled, locked out).
      return false;
    }
  }

  /// Exponential lockout after [maxAttempts] failures: 30s, 60s, 120s, ...
  Future<PinResult> verifyPin(String pin) async {
    final lockout = await lockedOutUntil();
    if (lockout != null) return PinLockedOut(lockout);

    final encoded = await _storage.read(key: _pinKey);
    if (encoded != null && await _hasher.verify(pin, encoded)) {
      await _resetFailures();
      return const PinAccepted();
    }

    final failures = int.parse(await _storage.read(key: _failKey) ?? '0') + 1;
    await _storage.write(key: _failKey, value: '$failures');
    if (failures >= maxAttempts) {
      final rounds = failures - maxAttempts;
      final until = _clock().add(
        Duration(seconds: 30 * pow(2, min(rounds, 8)).toInt()),
      );
      await _storage.write(key: _lockoutKey, value: until.toIso8601String());
      return PinLockedOut(until);
    }
    return PinRejected(attemptsLeft: maxAttempts - failures);
  }

  Future<DateTime?> lockedOutUntil() async {
    final raw = await _storage.read(key: _lockoutKey);
    if (raw == null) return null;
    final until = DateTime.parse(raw);
    return until.isAfter(_clock()) ? until : null;
  }

  Future<void> _resetFailures() async {
    await _storage.delete(key: _failKey);
    await _storage.delete(key: _lockoutKey);
  }
}
