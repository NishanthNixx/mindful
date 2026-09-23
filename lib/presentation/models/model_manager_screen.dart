import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/data/ai/model_manager.dart';
import 'package:mindfull/domain/ai/device_profile.dart';
import 'package:mindfull/domain/ai/model_spec.dart';
import 'package:mindfull/domain/ai/model_status.dart';
import 'package:mindfull/presentation/shared/appearance.dart';
import 'package:mindfull/presentation/shared/format.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart';
import 'package:mindfull/presentation/shared/network_indicator.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';
import 'package:mindfull/presentation/shared/pill.dart';

final FutureProvider<DeviceProfile> deviceProfileProvider =
    FutureProvider.autoDispose<DeviceProfile>(
      (ref) => ref.watch(modelManagerProvider).refreshDevice(),
    );

/// Start a download with the mobile-data and storage checks. Shared by the
/// model manager and the Ask tab.
Future<void> startModelDownload(
  BuildContext context,
  WidgetRef ref,
  ModelSpec model,
) async {
  final manager = ref.read(modelManagerProvider);
  if (await ref.read(onMobileDataProvider)()) {
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.signal_cellular_alt),
        title: const Text("You're on mobile data"),
        content: Text(
          '${model.displayName} is ${formatBytes(model.sizeBytes)}. Downloading it over mobile data may use '
          'a large part of your plan. Wi-Fi is recommended.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Wait for Wi-Fi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Download anyway'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  try {
    await manager.download(model);
  } on InsufficientStorage catch (e) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.sd_storage_outlined),
        title: const Text('Not enough space'),
        content: Text(
          'Free up about ${formatBytes(e.bytesToFree)} on this phone, then try again. '
          'Mindfull keeps some room spare so your phone never fills up completely.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class ModelManagerScreen extends ConsumerWidget {
  const ModelManagerScreen({super.key});

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ModelSpec model,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${model.displayName}?'),
        content: Text(
          'Frees ${formatBytes(model.sizeBytes)}. Your journal is not affected. You can download it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(modelManagerProvider).remove(model);
    ref.invalidate(deviceProfileProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(modelStatusProvider);
    final device = ref.watch(deviceProfileProvider);
    final theme = Theme.of(context);

    return MindfullScaffold(
      title: 'On-device AI',
      scene: Scene.settings,
      showOverline: false,
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
      ),
      actions: const [NetworkIndicator(), SizedBox(width: 8)],
      body: (context, padding) => ListView(
        padding: padding,
        children: [
          switch (device) {
            AsyncData(:final value) => _DeviceCard(device: value),
            AsyncError() => const _DeviceCard(device: null),
            _ => const SizedBox(
              height: 92,
              child: Center(child: CircularProgressIndicator()),
            ),
          },
          const SizedBox(height: 16),
          _StatusCard(
            status: status,
            device: device.value,
            onDownload: (m) => startModelDownload(context, ref, m),
            onPause: () => ref.read(modelManagerProvider).pause(),
            onCancel: (m) => ref.read(modelManagerProvider).cancel(m),
            onRemove: (m) => _confirmRemove(context, ref, m),
          ),
          if (device.value case final d?
              when _otherModels(d, status).isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionLabel('Other models for this phone'),
            const SizedBox(height: 12),
            for (final m in _otherModels(d, status))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ModelTile(
                  model: m,
                  device: d,
                  enabled: status is ModelNotInstalled || status is ModelFailed,
                  onDownload: () => startModelDownload(context, ref, m),
                ),
              ),
          ],
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Only the model file is downloaded, from Hugging Face. Nothing from your journal is sent — '
                  'the model runs entirely on this phone, even in airplane mode. Keep Mindfull open while it '
                  'downloads; if it stops, it resumes where it left off.',
                  style: theme.textTheme.labelSmall?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Compatible models other than the one shown in the status card.
  static List<ModelSpec> _otherModels(DeviceProfile d, ModelStatus s) {
    final current = switch (s) {
      ModelDownloading(:final model) ||
      ModelVerifying(:final model) ||
      ModelInstalled(:final model) ||
      ModelLoading(:final model) ||
      ModelReady(:final model) => model,
      ModelFailed(:final model) => model,
      _ => switch (recommendModel(d)) {
        Recommended(:final model) => model,
        NotSupported() => null,
      },
    };
    return [
      for (final m in compatibleModels(d))
        if (m != current) m,
    ];
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final DeviceProfile? device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = device;
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
    return PaperCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.phone_iphone,
                size: 20,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d == null
                      ? "Couldn't read this phone's details"
                      : 'This phone · ${d.model}',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ],
          ),
          if (d != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                stat('Memory', formatBytes(d.totalRamBytes)),
                stat('Free storage', formatBytes(d.freeDiskBytes)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.device,
    required this.enabled,
    required this.onDownload,
  });

  final ModelSpec model;
  final DeviceProfile device;
  final bool enabled;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaperCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${model.displayName} · ${formatBytes(model.sizeBytes)}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(model.summary, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: enabled ? onDownload : null,
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.device,
    required this.onDownload,
    required this.onPause,
    required this.onCancel,
    required this.onRemove,
  });

  final ModelStatus status;
  final DeviceProfile? device;
  final void Function(ModelSpec) onDownload;
  final VoidCallback onPause;
  final void Function(ModelSpec) onCancel;
  final void Function(ModelSpec) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = MindfullTokens.of(context);

    Widget header(
      String title, {
      String? pill,
      IconData icon = Icons.auto_awesome_outlined,
    }) => Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.6),
          child: Icon(icon, size: 20, color: scheme.secondary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
        if (pill != null)
          Pill(
            dense: true,
            label: pill,
            background: scheme.secondaryContainer.withValues(alpha: 0.6),
            foreground: scheme.secondary,
          ),
      ],
    );

    final children = switch (status) {
      ModelNotInstalled() => switch (device) {
        null => [const Center(child: CircularProgressIndicator())],
        final d => switch (recommendModel(d)) {
          Recommended(:final model, :final fitsStorage) => [
            header(model.displayName, pill: 'Recommended'),
            const SizedBox(height: 10),
            Text(model.summary, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              '${formatBytes(model.sizeBytes)} download · ${model.license} licence',
              style: theme.textTheme.labelSmall,
            ),
            if (!fitsStorage) ...[
              const SizedBox(height: 10),
              Text(
                'Needs ${formatBytes(model.sizeBytes + storageHeadroomBytes)} free. Free up some space first.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onDownload(model),
              icon: const Icon(Icons.download_rounded),
              label: Text('Download ${formatBytes(model.sizeBytes)}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
          NotSupported(:final reason) => [
            header('On-device AI is off', icon: Icons.memory),
            const SizedBox(height: 10),
            Text(reason, style: theme.textTheme.bodySmall),
          ],
        },
      },
      ModelUnsupported(:final reason) => [
        header('On-device AI is off', icon: Icons.memory),
        const SizedBox(height: 10),
        Text(reason, style: theme.textTheme.bodySmall),
      ],
      ModelDownloading(
        :final model,
        :final receivedBytes,
        :final totalBytes,
        :final bytesPerSecond,
        :final paused,
      ) =>
        [
          header(
            model.displayName,
            pill: paused ? 'Paused' : 'Downloading',
            icon: Icons.download_rounded,
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: totalBytes == 0 ? null : receivedBytes / totalBytes,
          ),
          const SizedBox(height: 8),
          Text(
            [
              '${formatBytes(receivedBytes)} of ${formatBytes(totalBytes)}',
              if (!paused && bytesPerSecond > 0)
                '${formatBytes(bytesPerSecond)}/s',
              if (!paused)
                ?formatEta(totalBytes - receivedBytes, bytesPerSecond),
            ].join(' · '),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: paused
                    ? FilledButton.icon(
                        onPressed: () => onDownload(model),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Resume'),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: onPause,
                        icon: const Icon(Icons.pause_rounded),
                        label: const Text('Pause'),
                      ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => onCancel(model),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ModelVerifying(:final model, :final progress) => [
        header(
          model.displayName,
          pill: 'Verifying',
          icon: Icons.fact_check_outlined,
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text(
          'Checking the file is complete and untampered (SHA-256)…',
          style: theme.textTheme.labelSmall,
        ),
      ],
      ModelInstalled(:final model) ||
      ModelLoading(:final model) ||
      ModelReady(:final model) => [
        header(
          model.displayName,
          pill: status is ModelLoading ? 'Loading…' : 'Installed',
          icon: Icons.check_circle_outline,
        ),
        const SizedBox(height: 10),
        Text(
          status is ModelReady
              ? 'Loaded and running on this phone.'
              : 'Downloaded and verified. It loads into memory when you open Ask.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${formatBytes(model.sizeBytes)} on this phone · ${model.license} licence',
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: status is ModelLoading ? null : () => onRemove(model),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove model'),
        ),
      ],
      ModelFailed(:final message, :final model, :final canResume) => [
        header(
          model?.displayName ?? 'Something went wrong',
          pill: 'Stopped',
          icon: Icons.error_outline,
        ),
        const SizedBox(height: 10),
        Text(message, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        if (model != null)
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onDownload(model),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(canResume ? 'Resume' : 'Try again'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => onRemove(model),
                child: const Text('Remove'),
              ),
            ],
          ),
      ],
    };

    return PaperCard(
      padding: const EdgeInsets.all(20),
      color: t.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
