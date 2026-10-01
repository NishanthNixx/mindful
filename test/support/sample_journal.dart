import 'package:mindfull/domain/entities/journal_entry.dart';

/// "Now" for journal-search tests: Wednesday 23 September 2026, 10:00.
final sampleNow = DateTime(2026, 9, 23, 10);

JournalEntry _e(
  String id,
  int month,
  int day,
  int mood,
  double? sleep,
  String note, {
  List<String> symptoms = const [],
  List<String> meds = const [],
}) => JournalEntry(
  id: id,
  createdAt: DateTime(2026, month, day, 20),
  mood: mood,
  sleepHours: sleep,
  note: note,
  symptoms: symptoms,
  medications: meds,
);

/// A small migraine journal whose right answers are known.
final List<JournalEntry> sampleJournal = [
  _e('aug-river', 8, 20, 4, 7.5, 'Good day, walked by the river with friends.'),
  _e(
    'sep02-migraine',
    9,
    2,
    2,
    5,
    'Migraine after a late night.',
    symptoms: ['Migraine'],
    meds: ['Sumatriptan 50mg'],
  ),
  _e(
    'sep10-headache',
    9,
    10,
    3,
    5.5,
    'Mild headache in the afternoon, skipped lunch.',
    symptoms: ['Headache'],
  ),
  _e(
    'sep12-worst',
    9,
    12,
    1,
    4.5,
    'Worst migraine this month, aura at work.',
    symptoms: ['Migraine', 'Nausea'],
    meds: ['Sumatriptan 50mg'],
  ),
  _e(
    'sep15-migraine',
    9,
    15,
    2,
    5,
    'Another migraine, dark room all evening.',
    symptoms: ['Migraine', 'Light sensitivity'],
  ),
  _e('sep18-run', 9, 18, 5, 8.5, 'Great run in the morning, felt strong.'),
  _e('sep20-yoga', 9, 20, 4, 8, 'Yoga and an early night. Calm.'),
  _e(
    'sep21-anxious',
    9,
    21,
    2,
    6,
    'Anxious before the presentation.',
    symptoms: ['Anxiety'],
  ),
  _e(
    'sep22-screen',
    9,
    22,
    3,
    7,
    'Slight headache after too much screen time.',
    symptoms: ['Headache'],
  ),
];
