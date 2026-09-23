import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/data/db/app_database.dart';
import 'package:mindfull/data/repositories/drift_journal_repo.dart';
import 'package:mindfull/domain/entities/entry_filter.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/entities/tag.dart';

void main() {
  late AppDatabase db;
  late DriftJournalRepo repo;

  JournalEntry entry(
    String id,
    int day, {
    int mood = 3,
    List<String> symptoms = const [],
    List<String> meds = const [],
  }) => JournalEntry(
    id: id,
    createdAt: DateTime(2026, 9, day, 9),
    mood: mood,
    symptoms: symptoms,
    medications: meds,
  );

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = DriftJournalRepo(db);
  });

  tearDown(() => db.close());

  test('save and read back with tags', () async {
    await repo.saveEntry(
      entry('a', 1, symptoms: ['migraine', 'nausea'], meds: ['sumatriptan']),
    );
    final got = await repo.getEntry('a');
    expect(got!.symptoms, ['migraine', 'nausea']);
    expect(got.medications, ['sumatriptan']);
  });

  test('update replaces tags', () async {
    await repo.saveEntry(entry('a', 1, symptoms: ['migraine']));
    await repo.saveEntry(entry('a', 1, symptoms: ['fatigue']));
    expect((await repo.getEntry('a'))!.symptoms, ['fatigue']);
  });

  test('tags are matched case-insensitively', () async {
    await repo.saveEntry(entry('a', 1, symptoms: ['Headache']));
    await repo.saveEntry(entry('b', 2, symptoms: ['headache']));
    final tags = await repo.watchTags(TagKind.symptom).first;
    expect(tags, hasLength(1));
    expect(tags.single.name, 'Headache');
    expect(tags.single.count, 2);
  });

  test('entries are newest first', () async {
    await repo.saveEntry(entry('old', 1));
    await repo.saveEntry(entry('new', 5));
    final all = await repo.watchEntries().first;
    expect(all.map((e) => e.id), ['new', 'old']);
  });

  test('filters by date range, mood and tag', () async {
    await repo.saveEntry(entry('a', 1, mood: 1, symptoms: ['migraine']));
    await repo.saveEntry(entry('b', 3, mood: 4, symptoms: ['migraine']));
    await repo.saveEntry(entry('c', 5, mood: 5));
    await repo.saveEntry(entry('d', 7, mood: 2, meds: ['ibuprofen']));

    Future<List<String>> ids(EntryFilter f) async =>
        (await repo.watchEntries(f).first).map((e) => e.id).toList();

    expect(
      await ids(
        EntryFilter(from: DateTime(2026, 9, 3), to: DateTime(2026, 9, 6)),
      ),
      ['c', 'b'],
    );
    expect(await ids(const EntryFilter(minMood: 4)), ['c', 'b']);
    expect(await ids(const EntryFilter(maxMood: 2)), ['d', 'a']);
    expect(await ids(const EntryFilter(tags: {'migraine'})), ['b', 'a']);
    expect(await ids(const EntryFilter(tags: {'migraine', 'ibuprofen'})), [
      'd',
      'b',
      'a',
    ]);
    expect(await ids(const EntryFilter(tags: {'migraine'}, minMood: 3)), ['b']);
  });

  test(
    'delete cascades to entry tags but keeps the tag for quick-pick',
    () async {
      await repo.saveEntry(entry('a', 1, symptoms: ['migraine']));
      await repo.deleteEntry('a');
      expect(await repo.getEntry('a'), isNull);
      final tags = await repo.watchTags(TagKind.symptom).first;
      expect(tags.single.count, 0);
    },
  );

  test('watchEntries emits on change', () async {
    final stream = repo.watchEntries();
    final expectation = expectLater(
      stream.map((l) => l.length),
      emitsInOrder([0, 1, 0]),
    );
    await pumpEventQueue();
    await repo.saveEntry(entry('a', 1));
    await pumpEventQueue();
    await repo.deleteEntry('a');
    await expectation;
  });

  test('deleteAll wipes everything', () async {
    await repo.saveEntry(entry('a', 1, symptoms: ['migraine']));
    await repo.deleteAll();
    expect(await repo.watchEntries().first, isEmpty);
    expect(await repo.watchTags(TagKind.symptom).first, isEmpty);
  });
}
