import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/router.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/domain/ai/model_status.dart';
import 'package:mindfull/presentation/lock/lock_controller.dart';
import 'package:mindfull/presentation/settings/lock_settings_providers.dart';
import 'package:mindfull/presentation/shared/appearance.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart';
import 'package:mindfull/presentation/shared/network_indicator.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';
import 'package:mindfull/presentation/shared/pill.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Delete all journal data?'),
        content: const Text(
          "Every entry, symptom and medication on this phone will be permanently erased. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(journalRepoProvider).deleteAll();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('All journal data deleted')));
    }
  }

  Future<void> _openLock(
    BuildContext context,
    WidgetRef ref, [
    String? action,
  ]) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await context.push<String>(
      action == null ? Routes.lockSetup : '${Routes.lockSetup}?action=$action',
    );
    refreshLockSettings(ref);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockOn = ref.watch(lockEnabledProvider).value ?? false;
    final bioAvailable = ref.watch(biometricsAvailableProvider).value ?? false;
    final bioOn = ref.watch(biometricsEnabledProvider).value ?? false;
    final nature = ref.watch(natureBackgroundsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final model = ref.watch(modelStatusProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget section(String label, IconData icon, Widget card) => Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(icon, size: 18, color: scheme.secondary),
              ],
            ),
          ),
          card,
        ],
      ),
    );

    return MindfullScaffold(
      title: 'Settings',
      scene: Scene.settings,
      actions: const [NetworkIndicator(), SizedBox(width: 8)],
      body: (context, padding) => ListView(
        padding: padding,
        children: [
          const _SanctuaryCard(),
          section(
            'Device security',
            Icons.lock_outline,
            PaperCard(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('App lock'),
                    subtitle: Text(
                      lockOn
                          ? 'Locks after 30s in background'
                          : 'Protect your journal with a PIN',
                    ),
                    value: lockOn,
                    onChanged: (v) =>
                        _openLock(context, ref, v ? null : 'disable'),
                  ),
                  SwitchListTile(
                    title: const Text('Face ID / Biometrics'),
                    subtitle: Text(
                      !lockOn
                          ? 'Turn on app lock first'
                          : bioAvailable
                          ? 'Unlock without typing your PIN'
                          : 'Not available on this device',
                    ),
                    value: lockOn && bioAvailable && bioOn,
                    onChanged: lockOn && bioAvailable
                        ? (v) async {
                            await ref
                                .read(appLockServiceProvider)
                                .setBiometrics(enabled: v);
                            refreshLockSettings(ref);
                          }
                        : null,
                  ),
                  if (lockOn) ...[
                    ListTile(
                      leading: const Icon(Icons.pin_outlined),
                      title: const Text('Change PIN'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openLock(context, ref, 'change'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => ref
                              .read(lockControllerProvider.notifier)
                              .lockNow(),
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: const Text('Lock now'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          section(
            'Data sovereignty',
            Icons.verified_user_outlined,
            PaperCard(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.secondaryContainer.withValues(
                        alpha: 0.7,
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        color: scheme.secondary,
                      ),
                    ),
                    title: const Text('What stays on this phone'),
                    subtitle: const Text(
                      'AES-256 on-device storage · No cloud sync · Works in airplane mode',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.privacy),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: const Text('Cloud AI fallback'),
                    subtitle: Text(
                      'Always off. Your notes never leave this phone.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.secondary,
                      ),
                    ),
                    value: false,
                    onChanged: null,
                  ),
                ],
              ),
            ),
          ),
          section(
            'On-device intelligence',
            Icons.memory,
            _ModelCard(status: model),
          ),
          section(
            'Appearance',
            Icons.landscape_outlined,
            PaperCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    title: const Text('Theme'),
                    subtitle: Text(switch (themeMode) {
                      ThemeMode.system => 'Follows your phone',
                      ThemeMode.light => 'Always light',
                      ThemeMode.dark =>
                        'Always dark — easier on the eyes at night',
                    }),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_outlined),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (s) =>
                            ref.read(themeModeProvider.notifier).set(s.single),
                      ),
                    ),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  SwitchListTile(
                    title: const Text('Nature backgrounds'),
                    subtitle: const Text(
                      'Soft forest and meadow photos behind your pages',
                    ),
                    value: nature,
                    onChanged: (v) => ref
                        .read(natureBackgroundsProvider.notifier)
                        .set(enabled: v),
                  ),
                ],
              ),
            ),
          ),
          section(
            'Data control',
            Icons.tune,
            PaperCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.errorContainer.withValues(alpha: 0.6),
                  child: Icon(
                    Icons.delete_forever_outlined,
                    color: scheme.error,
                  ),
                ),
                title: Text(
                  'Erase all data',
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: const Text(
                  'Permanently delete every entry on this phone',
                ),
                trailing: Icon(Icons.chevron_right, color: scheme.error),
                onTap: () => _deleteAll(context, ref),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const _About(),
        ],
      ),
    );
  }
}

class _SanctuaryCard extends StatelessWidget {
  const _SanctuaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PaperCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.secondaryContainer.withValues(
                  alpha: 0.7,
                ),
                child: Icon(
                  Icons.health_and_safety_outlined,
                  color: scheme.secondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SANCTUARY MODE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.secondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your private refuge',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Everything written here stays on this phone. No accounts, no trackers, no network calls.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MindfullTokens.of(context).canvas.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MindfullTokens.of(context).cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.secondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Network: Off',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.secondary,
                    ),
                  ),
                ),
                Pill(
                  dense: true,
                  label: 'AES-256',
                  background: scheme.secondaryContainer.withValues(alpha: 0.6),
                  foreground: scheme.secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.status});

  final ModelStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (title, subtitle, active) = switch (status) {
      ModelReady(:final model) => (
        model.displayName,
        'Loaded and running on this phone',
        true,
      ),
      ModelInstalled(:final model) => (
        model.displayName,
        'Installed · loads when you open Ask',
        true,
      ),
      ModelLoading(:final model) => (
        model.displayName,
        'Loading into memory…',
        true,
      ),
      ModelDownloading(:final model, :final progress, :final paused) => (
        model.displayName,
        paused
            ? 'Download paused at ${(progress * 100).round()}%'
            : 'Downloading… ${(progress * 100).round()}%',
        false,
      ),
      ModelVerifying(:final model) => (
        model.displayName,
        'Verifying the download…',
        false,
      ),
      ModelFailed(:final model, :final message) => (
        model?.displayName ?? 'On-device AI',
        message,
        false,
      ),
      ModelUnsupported(:final reason) => ('On-device AI is off', reason, false),
      ModelNotInstalled() => (
        'No model installed',
        'Download a small AI model to ask questions privately, on this phone.',
        false,
      ),
    };
    return PaperCard(
      padding: const EdgeInsets.all(20),
      onTap: status is ModelUnsupported
          ? null
          : () => context.push(Routes.models),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? scheme.secondary : scheme.outlineVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (status is! ModelUnsupported) const Icon(Icons.chevron_right),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: theme.textTheme.bodySmall),
          if (status
              case ModelDownloading(:final progress) ||
                  ModelVerifying(:final progress)) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
          ],
          if (status is! ModelUnsupported) ...[
            const SizedBox(height: 12),
            Text(
              'Manage models & storage',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const Emblem(size: 44),
        const SizedBox(height: 10),
        Text('Mindfull 0.1.0', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        const Pill(dense: true, label: 'Offline local build'),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Mindfull is a personal wellness journal, not medical advice. '
            'It does not diagnose or treat any condition — talk to a healthcare professional about your health.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Mindfull',
            applicationVersion: '0.1.0',
          ),
          child: const Text('Open-source licences'),
        ),
      ],
    );
  }
}
