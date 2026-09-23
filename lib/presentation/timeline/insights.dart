import 'package:collection/collection.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';

/// Plain aggregates for the timeline card. Kept separate from widgets so it is
/// unit-testable and reusable by the weekly summary later.
class JournalInsights {
  JournalInsights._({
    required this.days,
    required this.dailyMood,
    required this.entryCount,
    required this.averageMood,
    required this.averageSleep,
    required this.topSymptoms,
  });

  /// Buckets entries into calendar days from [start] (inclusive) to [end]
  /// (exclusive).
  factory JournalInsights.compute(
    List<JournalEntry> entries, {
    required DateTime start,
    required DateTime end,
  }) {
    final first = DateTime(start.year, start.month, start.day);
    final days = <DateTime>[
      for (
        var d = first;
        d.isBefore(end);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
    final inRange = entries
        .where((e) => !e.createdAt.isBefore(first) && e.createdAt.isBefore(end))
        .toList();

    final byDay = groupBy(
      inRange,
      (e) => DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day),
    );
    final dailyMood = [
      for (final d in days) byDay[d]?.map((e) => e.mood).average,
    ];

    final sleep = inRange.map((e) => e.sleepHours).nonNulls.toList();
    final symptomCounts = <String, int>{};
    for (final e in inRange) {
      for (final s in e.symptoms) {
        symptomCounts.update(s, (c) => c + 1, ifAbsent: () => 1);
      }
    }
    final top = symptomCounts.entries
        .sorted((a, b) => b.value.compareTo(a.value))
        .take(3)
        .toList();

    return JournalInsights._(
      days: days,
      dailyMood: dailyMood,
      entryCount: inRange.length,
      averageMood: inRange.isEmpty ? null : inRange.map((e) => e.mood).average,
      averageSleep: sleep.isEmpty ? null : sleep.average,
      topSymptoms: top,
    );
  }

  /// Mood direction across the range, or null with too little data.
  String? get trendLabel {
    final logged = dailyMood.nonNulls.toList();
    if (logged.length < 4) return null;
    final half = logged.length ~/ 2;
    final diff = logged.skip(half).average - logged.take(half).average;
    if (diff > 0.4) return 'Gently rising';
    if (diff < -0.4) return 'Dipping lately';
    return 'Steady';
  }

  final List<DateTime> days;

  /// Parallel to [days]; null where nothing was logged.
  final List<double?> dailyMood;
  final int entryCount;
  final double? averageMood;
  final double? averageSleep;
  final List<MapEntry<String, int>> topSymptoms;
}

/// A simple, explainable pattern found without the AI model, e.g. "Sleep
/// under 6 h came before 3 of 4 migraine entries". Phrased as a possible link,
/// never a cause.
class SleepPattern {
  const SleepPattern({
    required this.symptom,
    required this.shortSleep,
    required this.total,
  });

  static const shortSleepHours = 6.0;

  final String symptom;
  final int shortSleep;
  final int total;

  static SleepPattern? find(List<JournalEntry> entries) {
    final withSleep = entries.where((e) => e.sleepHours != null).toList();
    final counts = <String, int>{};
    for (final e in withSleep) {
      for (final s in e.symptoms) {
        counts.update(s, (c) => c + 1, ifAbsent: () => 1);
      }
    }
    SleepPattern? best;
    for (final MapEntry(key: symptom, value: total) in counts.entries) {
      if (total < 3) continue;
      final short = withSleep
          .where(
            (e) =>
                e.symptoms.contains(symptom) && e.sleepHours! < shortSleepHours,
          )
          .length;
      if (short < 2 || short / total < 0.5) continue;
      if (best == null || short / total > best.shortSleep / best.total) {
        best = SleepPattern(symptom: symptom, shortSleep: short, total: total);
      }
    }
    return best;
  }
}
