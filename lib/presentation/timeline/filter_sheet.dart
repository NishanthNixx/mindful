import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/domain/entities/entry_filter.dart';
import 'package:mindfull/domain/entities/tag.dart';
import 'package:mindfull/presentation/shared/mood.dart';

enum DatePreset {
  all('All time', null),
  week('7 days', 7),
  month('30 days', 30),
  quarter('90 days', 90),
  custom('Custom…', null)
  ;

  const DatePreset(this.label, this.days);

  final String label;
  final int? days;
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime presetStart(int days) {
  final t = _today();
  return DateTime(t.year, t.month, t.day - (days - 1));
}

DatePreset presetFor(EntryFilter f) {
  if (f.from == null && f.to == null) return DatePreset.all;
  if (f.to == null) {
    for (final p in [DatePreset.week, DatePreset.month, DatePreset.quarter]) {
      if (f.from == presetStart(p.days!)) return p;
    }
  }
  return DatePreset.custom;
}

String describeRange(EntryFilter f) {
  final preset = presetFor(f);
  if (preset != DatePreset.custom) {
    return preset == DatePreset.all ? 'All time' : 'Last ${preset.label}';
  }
  final fmt = DateFormat('d MMM');
  final end = f.to?.subtract(const Duration(days: 1));
  return '${f.from == null ? '…' : fmt.format(f.from!)} – ${end == null ? 'now' : fmt.format(end)}';
}

Future<void> showFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const _FilterSheet(),
  );
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late EntryFilter _f = ref.read(entryFilterProvider);

  Future<void> _pickPreset(DatePreset p) async {
    switch (p) {
      case DatePreset.all:
        setState(() => _f = _f.copyWith(from: () => null, to: () => null));
      case DatePreset.week || DatePreset.month || DatePreset.quarter:
        setState(
          () => _f = _f.copyWith(
            from: () => presetStart(p.days!),
            to: () => null,
          ),
        );
      case DatePreset.custom:
        final now = DateTime.now();
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: now,
          initialDateRange: _f.from == null
              ? null
              : DateTimeRange(
                  start: _f.from!,
                  end: _f.to?.subtract(const Duration(days: 1)) ?? now,
                ),
        );
        if (range == null) return;
        final end = range.end;
        setState(
          () => _f = _f.copyWith(
            from: () => range.start,
            to: () => DateTime(end.year, end.month, end.day + 1),
          ),
        );
    }
  }

  void _toggleTag(String name) {
    final tags = {..._f.tags};
    if (!tags.remove(name)) tags.add(name);
    setState(() => _f = _f.copyWith(tags: tags));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symptoms = ref.watch(tagsProvider(TagKind.symptom)).value ?? const [];
    final meds = ref.watch(tagsProvider(TagKind.medication)).value ?? const [];
    final preset = presetFor(_f);
    final minMood = _f.minMood ?? 1;
    final maxMood = _f.maxMood ?? 5;

    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );

    Widget tagChips(List<TagUsage> tags) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in tags)
          FilterChip(
            label: Text(t.name),
            selected: _f.tags.contains(t.name),
            onSelected: (_) => _toggleTag(t.name),
          ),
      ],
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                Text('Filter entries', style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                section(
                  'Date',
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in DatePreset.values)
                        ChoiceChip(
                          label: Text(
                            p == DatePreset.custom && preset == p
                                ? describeRange(_f)
                                : p.label,
                          ),
                          selected: preset == p,
                          onSelected: (_) => _pickPreset(p),
                        ),
                    ],
                  ),
                ),
                section(
                  'Mood: ${moodLabel(minMood)}${minMood == maxMood ? '' : ' to ${moodLabel(maxMood)}'}',
                  RangeSlider(
                    min: 1,
                    max: 5,
                    divisions: 4,
                    values: RangeValues(minMood.toDouble(), maxMood.toDouble()),
                    labels: RangeLabels(moodLabel(minMood), moodLabel(maxMood)),
                    onChanged: (v) => setState(
                      () => _f = _f.copyWith(
                        minMood: () =>
                            v.start.round() == 1 ? null : v.start.round(),
                        maxMood: () =>
                            v.end.round() == 5 ? null : v.end.round(),
                      ),
                    ),
                  ),
                ),
                if (symptoms.isNotEmpty)
                  section('Symptoms', tagChips(symptoms)),
                if (meds.isNotEmpty) section('Medications', tagChips(meds)),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _f.isEmpty
                        ? null
                        : () => setState(() => _f = const EntryFilter()),
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      ref.read(entryFilterProvider.notifier).set(_f);
                      Navigator.pop(context);
                    },
                    child: const Text('Show entries'),
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
