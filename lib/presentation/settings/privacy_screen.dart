import 'package:flutter/material.dart';
import 'package:mindfull/presentation/shared/appearance.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _items = <(IconData, String, String)>[
    (
      Icons.enhanced_encryption_outlined,
      'Encrypted database',
      'Entries, symptoms and medications are stored in a SQLCipher database (AES-256). '
          'The key is random, generated on this phone, and kept in the iOS Keychain / Android Keystore — '
          'never in the app files.',
    ),
    (
      Icons.cloud_off_outlined,
      'No network for your data',
      'Nothing you log is uploaded. The only planned network use is downloading the AI model, '
          'which you start yourself. The "Offline" badge changes when that happens.',
    ),
    (
      Icons.graphic_eq,
      'On-device dictation',
      "Voice notes use your phone's on-device speech recognition. If it isn't available for your language, "
          'dictation fails instead of falling back to a server.',
    ),
    (
      Icons.lock_outline,
      'App lock and app-switcher blur',
      'Optional PIN or biometric lock. The PIN is stored only as a salted PBKDF2 hash in the keystore. '
          'The app is hidden in the app switcher, and screenshots are blocked on Android.',
    ),
    (
      Icons.backup_outlined,
      'Not in cloud backups',
      "The encryption key is tied to this device and excluded from backups, so a restored backup can't be "
          'decrypted elsewhere. Android app-data backup is turned off.',
    ),
    (
      Icons.phone_android,
      "What this can't protect against",
      "Someone who has your phone unlocked while Mindfull is open can read what's on screen. "
          'Turn on app lock to add a second barrier.',
    ),
    (
      Icons.delete_outline,
      "You're in control",
      'Delete any entry, or erase everything from Settings. Deleted data is overwritten in the database file.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MindfullScaffold(
      title: 'Privacy',
      scene: Scene.settings,
      showOverline: false,
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
      ),
      body: (context, padding) => ListView(
        padding: padding,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
            child: Text(
              'Your journal never leaves this phone. There is no account, no server and no analytics on what you write.',
              style: theme.textTheme.bodyLarge,
            ),
          ),
          for (final (icon, title, body) in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PaperCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: scheme.secondaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      child: Icon(icon, size: 20, color: scheme.secondary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            body,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
