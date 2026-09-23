import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/presentation/shared/mood.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';
import 'package:mindfull/presentation/timeline/insights.dart';

/// "Gentle pattern noticed" — computed without the AI model.
class PatternCard extends StatelessWidget {
  const PatternCard({required this.pattern, super.key});

  final SleepPattern pattern;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = pattern;
    return PaperCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.7),
            child: Icon(Icons.spa_outlined, size: 20, color: scheme.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      'Gentle pattern noticed',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.secondary,
                      ),
                    ),
                    Text(
                      '· Sleep & ${p.symptom}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Sleep under ${SleepPattern.shortSleepHours.toStringAsFixed(0)} h came before '
                  '${p.shortSleep} of ${p.total} ${p.symptom.toLowerCase()} entries in this period. '
                  "It may be a link worth mentioning to your doctor — it isn't a diagnosis.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InsightsCard extends StatelessWidget {
  const InsightsCard({required this.insights, required this.title, super.key});

  final JournalInsights insights;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = insights;
    final avgMood = i.averageMood;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (i.trendLabel case final trend?)
                Text(
                  trend,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Stat(
                label: 'Reflections',
                value: Text(
                  '${i.entryCount}',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 6),
              _Stat(
                label: 'Avg mood',
                value: avgMood == null
                    ? Text('–', style: theme.textTheme.labelLarge)
                    : Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: moodColor(avgMood.round()),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              moodLabel(avgMood.round()),
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 6),
              _Stat(
                label: 'Avg sleep',
                value: Text(
                  i.averageSleep == null
                      ? '–'
                      : '${i.averageSleep!.toStringAsFixed(1)} hrs',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text('Mood rhythm', style: theme.textTheme.labelSmall),
              ),
              Text(
                '${DateFormat('d MMM').format(i.days.first)} – ${DateFormat('d MMM').format(i.days.last)}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(height: 64, child: _MoodRhythm(insights: i)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final t = MindfullTokens.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.canvas.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 28,
              child: Align(alignment: Alignment.centerLeft, child: value),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal, axis-free curve (the design's "hand-drawn tone curve"). Touch
/// shows the day and value.
class _MoodRhythm extends StatelessWidget {
  const _MoodRhythm({required this.insights});

  final JournalInsights insights;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = MindfullTokens.of(context).brand;
    final days = insights.days;
    final spots = [
      for (var x = 0; x < days.length; x++)
        if (insights.dailyMood[x] case final y?) FlSpot(x.toDouble(), y),
    ];
    final last = spots.isEmpty ? null : spots.last;

    return Semantics(
      label:
          'Mood rhythm over ${days.length} days. '
          'Average ${insights.averageMood == null ? 'not available' : moodLabel(insights.averageMood!.round())}.',
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: max(1, days.length - 1).toDouble(),
          minY: 0.6,
          maxY: 5.4,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              tooltipBorderRadius: BorderRadius.circular(12),
              getTooltipItems: (touched) => [
                for (final t in touched)
                  LineTooltipItem(
                    '${DateFormat('EEE d MMM').format(days[t.x.toInt()])}\n${moodLabel(t.y.round())}',
                    TextStyle(
                      color: scheme.onInverseSurface,
                      fontSize: 12,
                      fontFamily: 'PlusJakartaSans',
                    ),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.4,
              preventCurveOverShooting: true,
              color: line,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                checkToShowDot: (s, _) => s == last,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: scheme.primary,
                  strokeWidth: 5,
                  strokeColor: scheme.primary.withValues(alpha: 0.2),
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.secondaryContainer.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
