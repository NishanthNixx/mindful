import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/presentation/shared/mood.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';
import 'package:mindfull/presentation/shared/pill.dart';

String relativeTimestamp(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  final time = DateFormat.jm().format(t);
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Yesterday, $time';
  if (diff < 7) return '${DateFormat('EEE').format(t)}, $time';
  return DateFormat(t.year == n.year ? 'EEE, d MMM' : 'd MMM y').format(t);
}

class EntryTile extends StatelessWidget {
  const EntryTile({required this.entry, required this.onTap, super.key});

  final JournalEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = MindfullTokens.of(context);
    final e = entry;
    final ink = moodInk(e.mood, theme.brightness);

    return Semantics(
      button: true,
      child: PaperCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(
                        icon: moodIcon(e.mood),
                        label: '${e.mood} · ${moodLabel(e.mood)}',
                        semanticLabel: 'Mood: ${moodLabel(e.mood)}',
                        background: moodWash(e.mood, strength: 0.22),
                        foreground: ink,
                      ),
                      if (e.sleepHours != null)
                        Pill(
                          icon: Icons.bedtime_outlined,
                          label: '${_hours(e.sleepHours!)}h sleep',
                          dense: true,
                        ),
                      if (e.fromVoice)
                        const Pill(
                          icon: Icons.mic_none,
                          label: 'Dictated',
                          dense: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    relativeTimestamp(e.createdAt),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            if (e.note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                e.note,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ],
            if (e.symptoms.isNotEmpty || e.medications.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in e.symptoms) Pill(label: s, dense: true),
                  for (final m in e.medications)
                    Pill(
                      label: m,
                      dense: true,
                      icon: Icons.medication_outlined,
                      background: t.medChip.withValues(alpha: 0.5),
                      foreground: t.onMedChip,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _hours(double h) =>
      h == h.roundToDouble() ? h.toInt().toString() : h.toStringAsFixed(1);
}
