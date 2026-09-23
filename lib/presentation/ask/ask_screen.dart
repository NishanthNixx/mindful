import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/domain/ai/model_status.dart';
import 'package:mindfull/presentation/shared/appearance.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart';
import 'package:mindfull/presentation/shared/network_indicator.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';

const _examples = [
  'When did my headaches start getting worse?',
  'Summarise my week for my doctor',
  'Does poor sleep come before my migraines?',
];

class AskScreen extends ConsumerWidget {
  const AskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(modelStatusProvider);
    return MindfullScaffold(
      title: 'Ask',
      scene: Scene.ask,
      actions: const [NetworkIndicator(), SizedBox(width: 8)],
      body: (context, padding) => switch (status) {
        ModelReady() => const Center(child: Text('Ready')), // Week 3: chat UI.
        ModelNotInstalled() ||
        ModelDownloading() ||
        ModelUnsupported() => _NotReady(status: status, padding: padding),
      },
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.status});

  final ModelStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = MindfullTokens.of(context);
    final model = switch (status) {
      ModelReady() => 'Local model active',
      ModelDownloading() => 'Model downloading',
      ModelUnsupported() => 'AI off on this phone',
      ModelNotInstalled() => 'No model yet',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Network: Off · $model',
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.lock_outline,
            size: 15,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 4),
          Text(
            'On-device',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotReady extends StatelessWidget {
  const _NotReady({required this.status, required this.padding});

  final ModelStatus status;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (title, body) = switch (status) {
      ModelDownloading(:final progress) => (
        'Downloading model… ${(progress * 100).round()}%',
        'You can keep journaling while this finishes.',
      ),
      ModelUnsupported(:final reason) => (
        'On-device AI is off on this phone',
        reason,
      ),
      _ => (
        "On-device AI isn't set up yet",
        'Ask questions about your entries and get answers that cite them. The model runs entirely on this phone, '
            'so it works in airplane mode and nothing you write is sent anywhere.',
      ),
    };
    return ListView(
      padding: padding,
      children: [
        _StatusStrip(status: status),
        const SizedBox(height: 20),
        PaperCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: scheme.secondaryContainer.withValues(
                  alpha: 0.6,
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 28,
                  color: scheme.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
                textAlign: TextAlign.center,
              ),
              if (status case ModelDownloading(:final progress)) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: progress),
              ],
              if (status is ModelNotInstalled) ...[
                const SizedBox(height: 20),
                const FilledButton(
                  onPressed: null, // Week 2: opens the model manager.
                  child: Text('Download a model (coming soon)'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel("You'll be able to ask"),
        const SizedBox(height: 12),
        for (final q in _examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PaperCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              radius: 24,
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(q, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Local AI answers come only from your own entries. Not intended as medical advice.',
          style: theme.textTheme.labelSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
