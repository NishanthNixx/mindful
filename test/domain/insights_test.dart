import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/presentation/timeline/insights.dart';

void main() {
  JournalEntry e(
    int day,
    int mood, {
    double? sleep,
    List<String> symptoms = const [],
  }) => JournalEntry(
    id: '$day-$mood',
    createdAt: DateTime(2026, 9, day, 10),
    mood: mood,
    sleepHours: sleep,
    symptoms: symptoms,
  );

  test('buckets by day, averages and ranks symptoms', () {
    final i = JournalInsights.compute(
      [
        e(1, 2, sleep: 5, symptoms: ['migraine']),
        e(1, 4, sleep: 7, symptoms: ['migraine', 'nausea']),
        e(3, 5, symptoms: ['fatigue']),
        e(9, 1, symptoms: ['migraine']), // outside range
      ],
      start: DateTime(2026, 9, 1, 15), // normalised to midnight
      end: DateTime(2026, 9, 4),
    );

    expect(i.days, [
      DateTime(2026, 9),
      DateTime(2026, 9, 2),
      DateTime(2026, 9, 3),
    ]);
    expect(i.dailyMood, [3.0, null, 5.0]);
    expect(i.entryCount, 3);
    expect(i.averageMood, closeTo(11 / 3, 1e-9));
    expect(i.averageSleep, 6.0);
    expect(i.topSymptoms.first.key, 'migraine');
    expect(i.topSymptoms.first.value, 2);
  });

  test('handles DST-free day stepping across month end', () {
    final i = JournalInsights.compute(
      const [],
      start: DateTime(2026, 9, 29),
      end: DateTime(2026, 10, 2),
    );
    expect(i.days.length, 3);
    expect(i.averageMood, isNull);
  });
}
