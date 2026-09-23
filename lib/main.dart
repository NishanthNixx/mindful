import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/app.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/router.dart';
import 'package:mindfull/data/db/app_database.dart';
import 'package:mindfull/data/db/encrypted_connection.dart';
import 'package:mindfull/data/security/db_key_store.dart';
import 'package:mindfull/data/security/secure_store.dart';
import 'package:mindfull/presentation/onboarding/welcome_screen.dart';
import 'package:mindfull/presentation/shared/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [
      ('Literata', 'OFL-Literata.txt'),
      ('Plus Jakarta Sans', 'OFL-PlusJakartaSans.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });

  final storage = createSecureStorage();
  final key = await DbKeyStore(storage).getOrCreateKey();
  final db = AppDatabase(
    openEncryptedDatabase(await defaultDatabaseFile(), key),
  );
  final onboarded = await storage.read(key: WelcomeScreen.onboardedKey) != null;
  final nature =
      await storage.read(key: NatureBackgroundsNotifier.storageKey) == 'true';
  final themeMode = ThemeModeNotifier.parse(
    await storage.read(key: ThemeModeNotifier.storageKey),
  );

  runApp(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        databaseProvider.overrideWithValue(db),
        natureBackgroundsProvider.overrideWith(
          () => NatureBackgroundsNotifier(initial: nature),
        ),
        themeModeProvider.overrideWith(
          () => ThemeModeNotifier(initial: themeMode),
        ),
      ],
      child: MindfullApp(router: buildRouter(onboarded: onboarded)),
    ),
  );
}
