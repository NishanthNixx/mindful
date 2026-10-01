import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/router.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/data/ai/embedder_manager.dart';
import 'package:mindfull/domain/ai/model_spec.dart';
import 'package:mindfull/domain/ai/model_status.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/journal_search/prompt.dart';
import 'package:mindfull/presentation/ask/ask_controller.dart';
import 'package:mindfull/presentation/models/model_manager_screen.dart';
import 'package:mindfull/presentation/shared/appearance.dart';
import 'package:mindfull/presentation/shared/format.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart';
import 'package:mindfull/presentation/shared/mood.dart';
import 'package:mindfull/presentation/shared/network_indicator.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';
import 'package:mindfull/presentation/timeline/timeline_screen.dart'
    show openEditor;

const _examples = [
  'When did my headaches start getting worse?',
  'Summarise my week for my doctor',
  'Does poor sleep come before my migraines?',
];

const _journalStarters = [
  'When did my headaches start getting worse?',
  'How has my sleep been this month?',
  'What was going on on my good days?',
  'Summarise my last week',
];

const _starters = [
  'Tips for winding down before bed',
  'How can I spot my migraine triggers?',
  'What should I note in a symptom diary?',
];

class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  @override
  void initState() {
    super.initState();
    // Opening Ask is what loads an installed model into memory.
    unawaited(
      Future.microtask(() async {
        await ref.read(modelManagerProvider).ensureLoaded();
        // Warm up journal search so the first question doesn't wait for it.
        final search = ref.read(embedderManagerProvider);
        await search.restore();
        if (await search.ensureLoaded()) {
          await ref
              .read(journalIndexerProvider)
              .sync(ref.read(embedderRuntimeProvider));
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(modelStatusProvider);
    ref.listen(modelStatusProvider, (_, next) {
      if (next is ModelInstalled) {
        unawaited(ref.read(modelManagerProvider).ensureLoaded());
      }
    });
    final generating = ref.watch(
      askControllerProvider.select((s) => s.generating),
    );
    final hasMessages = ref.watch(
      askControllerProvider.select((s) => s.messages.isNotEmpty),
    );

    return MindfullScaffold(
      title: 'Ask',
      scene: Scene.ask,
      actions: [
        const NetworkIndicator(),
        if (status is ModelReady && hasMessages)
          IconButton(
            tooltip: 'New chat',
            onPressed: generating
                ? null
                : () => ref.read(askControllerProvider.notifier).newChat(),
            icon: const Icon(Icons.add_comment_outlined),
          )
        else
          const SizedBox(width: 8),
      ],
      body: (context, padding) => switch (status) {
        ModelReady(:final model) => _Chat(model: model, padding: padding),
        ModelInstalled(:final model) ||
        ModelLoading(:final model) => _Loading(model: model, padding: padding),
        _ => _NotReady(status: status, padding: padding),
      },
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = MindfullTokens.of(context);
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
              'Network: Off · $label',
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

// ---------------------------------------------------------------------------
// Ready: streaming chat.

class _Chat extends ConsumerStatefulWidget {
  const _Chat({required this.model, required this.padding});

  final ModelSpec model;
  final EdgeInsets padding;

  @override
  ConsumerState<_Chat> createState() => _ChatState();
}

class _ChatState extends ConsumerState<_Chat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final value = text ?? _input.text;
    if (value.trim().isEmpty) return;
    _input.clear();
    unawaited(ref.read(askControllerProvider.notifier).send(value));
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(askControllerProvider);
    final search = ref.watch(searchStatusProvider);
    final searchUsable = search is SearchInstalled || search is SearchReady;
    final canSend = state.mode == AskMode.general || searchUsable;
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomInset = keyboard ? 8.0 : widget.padding.bottom - 16;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: widget.padding.copyWith(bottom: 16),
            children: [
              _StatusStrip(label: '${widget.model.displayName} active'),
              const SizedBox(height: 14),
              SegmentedButton<AskMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AskMode.journal,
                    icon: Icon(Icons.auto_stories_outlined),
                    label: Text('Your journal'),
                  ),
                  ButtonSegment(
                    value: AskMode.general,
                    icon: Icon(Icons.chat_bubble_outline),
                    label: Text('General'),
                  ),
                ],
                selected: {state.mode},
                onSelectionChanged: state.generating
                    ? null
                    : (m) => ref
                          .read(askControllerProvider.notifier)
                          .setMode(m.single),
              ),
              const SizedBox(height: 16),
              if (state.mode == AskMode.journal && !searchUsable) ...[
                const _SearchSetupCard(),
                const SizedBox(height: 16),
              ],
              if (state.messages.isEmpty) ...[
                PaperCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.mode == AskMode.journal
                            ? 'Ask about your journal'
                            : 'Chat privately with ${widget.model.displayName}',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.mode == AskMode.journal
                            ? 'Answers come only from your own entries and cite them — tap a number to open '
                                  'the entry. Everything runs on this phone, even in airplane mode.'
                            : 'Every word is generated on this phone — try it in airplane mode. '
                                  "General chat doesn't look at your journal.",
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Try asking'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q
                        in state.mode == AskMode.journal
                            ? _journalStarters
                            : _starters)
                      ActionChip(
                        label: Text(q),
                        onPressed: canSend ? () => _send(q) : null,
                      ),
                  ],
                ),
              ],
              for (final m in state.messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: m.sender == Sender.user
                      ? _UserBubble(text: m.text.value)
                      : _AssistantCard(
                          message: m,
                          modelName: widget.model.displayName,
                          onStop: () =>
                              ref.read(askControllerProvider.notifier).stop(),
                          onGrow: _toBottom,
                        ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InputBar(
                controller: _input,
                generating: state.generating,
                enabled: canSend,
                hint: state.mode == AskMode.journal
                    ? 'Ask about your entries…'
                    : 'Ask anything, privately…',
                onSend: _send,
                onStop: () => ref.read(askControllerProvider.notifier).stop(),
              ),
              if (!keyboard) ...[
                const SizedBox(height: 6),
                Text(
                  'Answers are generated on this phone. Not medical advice.',
                  style: theme.textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = MindfullTokens.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: t.card,
            border: Border.all(color: t.cardBorder),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ),
    );
  }
}

class _AssistantCard extends StatelessWidget {
  const _AssistantCard({
    required this.message,
    required this.modelName,
    required this.onStop,
    required this.onGrow,
  });

  final ChatMessage message;
  final String modelName;
  final VoidCallback onStop;
  final VoidCallback onGrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final journal = message.mode == AskMode.journal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: MindfullTokens.of(context).brand,
              child: Icon(
                Icons.spa_outlined,
                size: 15,
                color: MindfullTokens.of(context).onBrand,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Mindfull Assistant',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.secondary,
              ),
            ),
            Flexible(
              child: Text(
                journal ? ' · from your journal' : ' · $modelName, on-device',
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PaperCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: ValueListenableBuilder<bool>(
            valueListenable: message.streaming,
            builder: (context, streaming, _) => ValueListenableBuilder<String>(
              valueListenable: message.text,
              builder: (context, text, _) {
                if (streaming) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => onGrow());
                }
                final cited = journal
                    ? citedNumbers(text, message.sources.length)
                    : const <int>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (text.isEmpty && streaming)
                      _Waiting(message: message)
                    else
                      _AnswerText(
                        text: text,
                        message: message,
                        streaming: streaming,
                      ),
                    if (cited.isNotEmpty && !streaming) ...[
                      const SizedBox(height: 16),
                      Text(
                        'REFERENCED JOURNAL ENTRIES',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final n in cited)
                        _SourceTile(number: n, entry: message.sources[n - 1]),
                    ] else if (journal &&
                        !streaming &&
                        message.sources.isNotEmpty &&
                        text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Searched ${message.sources.length} related entries',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (streaming)
                      ActionChip(
                        avatar: const Icon(Icons.stop_rounded, size: 18),
                        label: const Text('Stop generating'),
                        onPressed: onStop,
                      )
                    else
                      _Footer(message: message),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([message.phase, message.thinking]),
      builder: (context, _) => Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message.thinking.value
                  ? 'Thinking…'
                  : message.phase.value ?? 'Starting…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Answer text with `[n]` citations turned into tappable number chips.
class _AnswerText extends StatelessWidget {
  const _AnswerText({
    required this.text,
    required this.message,
    required this.streaming,
  });

  final String text;
  final ChatMessage message;
  final bool streaming;

  static final _citation = RegExp(r'\[(\d+(?:\s*[,;]\s*\d+)*)\]');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = MindfullTokens.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontFamily: 'Literata',
      fontSize: 19,
      height: 1.55,
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m
        in message.mode == AskMode.journal
            ? _citation.allMatches(text)
            : const <RegExpMatch>[]) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
      for (final raw in m.group(1)!.split(RegExp(r'\s*[,;]\s*'))) {
        final n = int.parse(raw);
        if (n < 1 || n > message.sources.length) continue;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _CitationChip(
              key: ValueKey('citation-$n'),
              number: n,
              entry: message.sources[n - 1],
            ),
          ),
        );
      }
      last = m.end;
    }
    spans.add(TextSpan(text: text.substring(last)));
    if (streaming) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.only(left: 3),
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: t.brand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }
    // Not SelectableText: its selection gestures would swallow taps on the
    // citation chips. The Copy button covers copying.
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({required this.number, required this.entry, super.key});

  final int number;
  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label:
          'Source $number: entry from ${DateFormat('EEEE d MMMM').format(entry.createdAt)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => openEditor(context, Routes.entry(entry.id)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$number',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.number, required this.entry});

  final int number;
  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = MindfullTokens.of(context);
    final e = entry;
    final headline = [
      DateFormat('EEE d MMM').format(e.createdAt),
      if (e.symptoms.isNotEmpty) e.symptoms.join(', ') else moodLabel(e.mood),
    ].join(' · ');
    final detail = [
      'Mood: ${moodLabel(e.mood)}',
      if (e.sleepHours case final h?)
        'Sleep: ${h == h.roundToDouble() ? h.toInt() : h}h',
      ...e.medications,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: t.canvas.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: t.cardBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => openEditor(context, Routes.entry(e.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: theme.colorScheme.secondaryContainer
                      .withValues(alpha: 0.8),
                  child: Text('$number', style: theme.textTheme.labelMedium),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        detail,
                        style: theme.textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchSetupCard extends ConsumerWidget {
  const _SearchSetupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(searchStatusProvider);
    final spec = ref.read(embedderManagerProvider).spec;
    return PaperCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Journal search needs one more small model',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            switch (status) {
              SearchDownloading(:final progress, :final paused) =>
                paused
                    ? 'Paused at ${(progress * 100).round()}%.'
                    : 'Downloading… ${(progress * 100).round()}%',
              SearchVerifying() => 'Checking the download…',
              SearchFailed(:final message) => message,
              _ =>
                'A ${formatBytes(spec.sizeBytes)} English search model lets Mindfull find the entries that '
                    'answer your question. Like everything else, it runs on this phone.',
            },
            style: theme.textTheme.bodySmall,
          ),
          if (status case SearchDownloading(:final progress)) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
          ],
          if (switch (status) {
            SearchNotInstalled() ||
            SearchFailed() ||
            SearchDownloading(paused: true) => true,
            _ => false,
          }) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => startSearchDownload(context, ref),
              icon: const Icon(Icons.download_rounded),
              label: Text(
                status is SearchNotInstalled
                    ? 'Download ${formatBytes(spec.sizeBytes)}'
                    : 'Resume',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = message.metrics;
    final parts = [
      if (message.error != null) message.error!,
      if (message.stopped) 'Stopped',
      if (m != null)
        '${(m.timeToFirstToken.inMilliseconds / 1000).toStringAsFixed(1)}s to first token',
      if (m?.tokensPerSecond case final tps?) '${tps.toStringAsFixed(1)} tok/s',
    ];
    return Row(
      children: [
        Expanded(
          child: Text(
            parts.join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: message.error != null ? theme.colorScheme.error : null,
            ),
          ),
        ),
        if (message.text.value.isNotEmpty)
          IconButton(
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message.text.value));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Copied')));
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.generating,
    required this.onSend,
    required this.onStop,
    this.enabled = true,
    this.hint = 'Ask anything, privately…',
  });

  final TextEditingController controller;
  final bool generating;
  final bool enabled;
  final String hint;
  final void Function([String?]) onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final t = MindfullTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              enabled: enabled,
              onSubmitted: generating ? null : onSend,
              decoration: InputDecoration(
                hintText: hint,
                filled: false,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          IconButton.filled(
            tooltip: generating ? 'Stop' : 'Send',
            style: IconButton.styleFrom(
              backgroundColor: t.brand,
              foregroundColor: t.onBrand,
              minimumSize: const Size(48, 48),
            ),
            onPressed: generating
                ? onStop
                : enabled
                ? onSend
                : null,
            icon: Icon(
              generating ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Not ready yet.

class _Loading extends StatelessWidget {
  const _Loading({required this.model, required this.padding});

  final ModelSpec model;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: padding,
      children: [
        _StatusStrip(label: 'Loading ${model.displayName}'),
        const SizedBox(height: 20),
        PaperCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Waking up ${model.displayName}…',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Loading ${formatBytes(model.sizeBytes)} into memory. This takes a few seconds the first time.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
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
    final (title, body, action) = switch (status) {
      ModelDownloading(:final model, :final progress, :final paused) => (
        paused
            ? 'Download paused'
            : 'Downloading ${model.displayName}… ${(progress * 100).round()}%',
        paused
            ? 'Resume it from the model manager.'
            : 'You can keep journaling while this finishes.',
        'Open model manager',
      ),
      ModelVerifying(:final progress) => (
        'Checking the download… ${(progress * 100).round()}%',
        'Making sure the file is complete and untampered.',
        null,
      ),
      ModelUnsupported(:final reason) => (
        'On-device AI is off on this phone',
        reason,
        null,
      ),
      ModelFailed(:final message) => (
        'The model needs attention',
        message,
        'Open model manager',
      ),
      _ => (
        "On-device AI isn't set up yet",
        'Ask questions and get answers generated entirely on this phone — it works in airplane mode and '
            'nothing you write is sent anywhere.',
        'Set up on-device AI',
      ),
    };
    final progress = switch (status) {
      ModelDownloading(:final progress) => progress,
      ModelVerifying(:final progress) => progress,
      _ => null,
    };
    return ListView(
      padding: padding,
      children: [
        const _StatusStrip(label: 'No model yet'),
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
              if (progress != null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: progress),
              ],
              if (action != null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.push(Routes.models),
                  child: Text(action),
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
