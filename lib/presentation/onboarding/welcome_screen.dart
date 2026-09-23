import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/router.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart'
    show Emblem;
import 'package:mindfull/presentation/shared/paper_card.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  static const onboardedKey = 'onboarded_v1';

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _acknowledged = false;

  Future<void> _start() async {
    await ref
        .read(secureStorageProvider)
        .write(key: WelcomeScreen.onboardedKey, value: 'true');
    if (mounted) context.go(Routes.timeline);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget point(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.6),
            child: Icon(icon, size: 20, color: scheme.secondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: MindfullTokens.of(context).canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Emblem(size: 64),
              ),
              const SizedBox(height: 20),
              Text('Mindfull', style: theme.textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                'A quiet, private journal for mood, symptoms, medication and sleep.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 36),
              point(
                Icons.phone_android,
                'Stays on your phone',
                'No account, no server. Everything is stored in an encrypted database on this device.',
              ),
              point(
                Icons.airplanemode_active,
                'Works offline',
                'Journaling — and later, the on-device AI — works in airplane mode.',
              ),
              point(
                Icons.lock_outline,
                'Lock it',
                'Add a PIN or Face ID lock any time in Settings.',
              ),
              const SizedBox(height: 8),
              PaperCard(
                radius: 24,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: CheckboxListTile(
                  value: _acknowledged,
                  onChanged: (v) => setState(() => _acknowledged = v ?? false),
                  title: Text(
                    'I understand Mindfull is a wellness journal, not medical advice.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _acknowledged ? _start : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text('Get started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
