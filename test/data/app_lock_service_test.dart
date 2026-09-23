import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/data/security/app_lock_service.dart';
import 'package:mindfull/data/security/pin_hasher.dart';
import 'package:mocktail/mocktail.dart';

class _MemoryStorage extends Mock implements FlutterSecureStorage {
  final data = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => value == null ? data.remove(key) : data[key] = value;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data.remove(key);
}

void main() {
  late _MemoryStorage storage;
  late DateTime now;
  late AppLockService service;

  setUp(() {
    storage = _MemoryStorage();
    now = DateTime(2026, 9, 23, 12);
    service = AppLockService(
      storage: storage,
      hasher: const PinHasher(iterations: 1000),
      clock: () => now,
    );
  });

  test('PBKDF2 matches RFC 7914 test vector', () async {
    const encoded =
        r'pbkdf2-sha256$4096$73616c74$c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a';
    expect(await const PinHasher().verify('password', encoded), isTrue);
    expect(await const PinHasher().verify('Password', encoded), isFalse);
  });

  test('PIN hash is salted and never stores the PIN', () async {
    await service.enable('4821', useBiometrics: false);
    final stored = storage.data['lock_pin_hash']!;
    expect(stored, startsWith(r'pbkdf2-sha256$1000$'));
    expect(stored, isNot(contains('4821')));

    final second = await const PinHasher(iterations: 1000).hash('4821');
    expect(second, isNot(stored), reason: 'random salt');
  });

  test('accepts correct PIN, rejects wrong PIN', () async {
    await service.enable('4821', useBiometrics: false);
    expect(await service.isEnabled(), isTrue);
    expect(await service.verifyPin('4821'), isA<PinAccepted>());
    final r = await service.verifyPin('0000');
    expect(
      r,
      isA<PinRejected>().having((r) => r.attemptsLeft, 'attemptsLeft', 4),
    );
  });

  test('locks out after max attempts and escalates', () async {
    await service.enable('4821', useBiometrics: false);
    for (var i = 0; i < AppLockService.maxAttempts - 1; i++) {
      await service.verifyPin('0000');
    }
    final locked = await service.verifyPin('0000');
    expect(
      locked,
      isA<PinLockedOut>().having(
        (l) => l.until,
        'until',
        now.add(const Duration(seconds: 30)),
      ),
    );

    // Even the right PIN is refused during lockout.
    expect(await service.verifyPin('4821'), isA<PinLockedOut>());

    now = now.add(const Duration(seconds: 31));
    final again = await service.verifyPin('1111');
    expect(
      again,
      isA<PinLockedOut>().having(
        (l) => l.until,
        'until',
        now.add(const Duration(seconds: 60)),
      ),
    );

    now = now.add(const Duration(seconds: 61));
    expect(await service.verifyPin('4821'), isA<PinAccepted>());
    expect(storage.data.containsKey('lock_failures'), isFalse);
  });

  test('disable clears everything', () async {
    await service.enable('4821', useBiometrics: true);
    await service.disable();
    expect(await service.isEnabled(), isFalse);
    expect(storage.data, isEmpty);
  });
}
