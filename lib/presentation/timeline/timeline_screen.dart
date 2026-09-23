import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/router.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/domain/entities/entry_filter.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/presentation/shared/appearance.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart';
import 'package:mindfull/presentation/shared/network_indicator.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';
import 'package:mindfull/presentation/shared/pill.dart';
import 'package:mindfull/presentation/timeline/entry_tile.dart';
import 'package:mindfull/presentation/timeline/filter_sheet.dart';
import 'package:mindfull/presentation/timeline/insights.dart';
import 'package:mindfull/presentation/timeline/insights_card.dart';

/// Opens the editor and shows its result ("Entry saved", ...) in this tab.
Future<void> openEditor(BuildContext context, String location) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await context.push<String>(location);
  if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
}

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(entriesProvider);
    final filter = ref.watch(entryFilterProvider);
    final t = MindfullTokens.of(context);

    return MindfullScaffold(
      title: 'Journal',
      scene: Scene.journal,
      actions: [
        const NetworkIndicator(),
        IconButton(
          tooltip: 'Filter',
          onPressed: () => showFilterSheet(context),
          icon: Badge(
            isLabelVisible: !filter.isEmpty,
            smallSize: 8,
            child: const Icon(Icons.tune),
          ),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openEditor(context, Routes.newEntry),
        backgroundColor: t.brand,
        foregroundColor: t.onBrand,
        elevation: 6,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.edit_note),
        label: Text(
          'Log Entry',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: t.onBrand),
        ),
      ),
      body: (context, padding) => switch (entries) {
        AsyncData(:final value) => _Body(
          entries: value,
          filter: filter,
          padding: padding,
        ),
        AsyncError(:final error) => Center(
          child: Text(
            'Could not load entries.\n$error',
            textAlign: TextAlign.center,
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.entries,
    required this.filter,
    required this.padding,
  });

  final List<JournalEntry> entries;
  final EntryFilter filter;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = clock.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final start = filter.from ?? presetStart(30);
    final end = filter.to ?? tomorrow;
    // Cap the chart at 90 days so long custom ranges stay readable.
    final chartStart = end.difference(start).inDays > 90
        ? end.subtract(const Duration(days: 90))
        : start;
    final insights = JournalInsights.compute(
      entries,
      start: chartStart,
      end: end,
    );
    final inRange = entries
        .where(
          (e) => !e.createdAt.isBefore(chartStart) && e.createdAt.isBefore(end),
        )
        .toList();
    final pattern = SleepPattern.find(inRange);

    const gap = SliverToBoxAdapter(child: SizedBox(height: 16));
    // Extra room so the last card clears the floating "Log Entry" button.
    final listPadding = padding.copyWith(bottom: padding.bottom + 72);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: listPadding.copyWith(bottom: 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Flexible(
                  child: Pill(
                    dense: true,
                    icon: Icons.health_and_safety_outlined,
                    label: 'Offline & encrypted on device',
                    background: MindfullTokens.of(context).card,
                    foreground: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  DateFormat('MMMM y').format(now),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
        if (!filter.isEmpty)
          SliverToBoxAdapter(child: _ActiveFilters(filter: filter)),
        if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Empty(filtered: !filter.isEmpty),
          )
        else
          SliverPadding(
            padding: listPadding.copyWith(top: 16),
            sliver: SliverMainAxisGroup(
              slivers: [
                if (pattern != null) ...[
                  SliverToBoxAdapter(child: PatternCard(pattern: pattern)),
                  gap,
                ],
                SliverToBoxAdapter(
                  child: InsightsCard(
                    insights: insights,
                    title: filter.from == null
                        ? 'Past 30 days'
                        : describeRange(filter),
                  ),
                ),
                gap,
                const SliverToBoxAdapter(
                  child: SectionLabel('Timeline entries'),
                ),
                gap,
                SliverList.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) => EntryTile(
                    entry: entries[i],
                    onTap: () =>
                        openEditor(context, Routes.entry(entries[i].id)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      'A tranquil mind unfolds one page at a time.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.filter});

  final EntryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(entryFilterProvider.notifier);
    final f = filter;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        spacing: 8,
        children: [
          if (f.from != null || f.to != null)
            InputChip(
              label: Text(describeRange(f)),
              onDeleted: () =>
                  notifier.set(f.copyWith(from: () => null, to: () => null)),
            ),
          if (f.minMood != null || f.maxMood != null)
            InputChip(
              label: Text('Mood ${f.minMood ?? 1}–${f.maxMood ?? 5}'),
              onDeleted: () => notifier.set(
                f.copyWith(minMood: () => null, maxMood: () => null),
              ),
            ),
          for (final t in f.tags)
            InputChip(
              label: Text(t),
              onDeleted: () =>
                  notifier.set(f.copyWith(tags: {...f.tags}..remove(t))),
            ),
          TextButton(onPressed: notifier.clear, child: const Text('Clear all')),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 160),
      child: Center(
        child: PaperCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.6),
                child: Icon(
                  filtered ? Icons.filter_alt_off_outlined : Icons.spa_outlined,
                  size: 30,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                filtered ? 'No entries match' : 'Your journal is empty',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                filtered
                    ? 'Try widening the date range or removing a tag.'
                    : 'Log how you feel, any symptoms, medication and sleep. Everything stays on this phone.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
