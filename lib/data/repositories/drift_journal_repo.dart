import 'package:drift/drift.dart';
import 'package:mindfull/data/db/app_database.dart';
import 'package:mindfull/domain/entities/entry_filter.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/entities/tag.dart';
import 'package:mindfull/domain/repositories/journal_repo.dart';

class DriftJournalRepo implements JournalRepo {
  DriftJournalRepo(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Stream<List<JournalEntry>> watchEntries([
    EntryFilter filter = const EntryFilter(),
  ]) {
    final e = _db.entries;
    final query = _db.select(e)
      ..where((row) {
        final conditions = <Expression<bool>>[
          if (filter.from != null)
            row.createdAt.isBiggerOrEqualValue(filter.from!),
          if (filter.to != null) row.createdAt.isSmallerThanValue(filter.to!),
          if (filter.minMood != null)
            row.mood.isBiggerOrEqualValue(filter.minMood!),
          if (filter.maxMood != null)
            row.mood.isSmallerOrEqualValue(filter.maxMood!),
          if (filter.tags.isNotEmpty)
            row.id.isInQuery(_entryIdsWithAnyTag(filter.tags)),
        ];
        return conditions.isEmpty
            ? const Constant(true)
            : Expression.and(conditions);
      })
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    return query.watch().asyncMap(_withTags);
  }

  BaseSelectStatement<TypedResult> _entryIdsWithAnyTag(Set<String> names) {
    final et = _db.entryTags;
    final t = _db.tags;
    return _db.selectOnly(et).join([innerJoin(t, t.id.equalsExp(et.tagId))])
      ..addColumns([et.entryId])
      ..where(t.name.isIn(names));
  }

  Future<List<JournalEntry>> _withTags(List<EntryRow> rows) async {
    if (rows.isEmpty) return const [];
    final et = _db.entryTags;
    final t = _db.tags;
    final tagRows =
        await (_db.select(et).join([innerJoin(t, t.id.equalsExp(et.tagId))])
              ..where(et.entryId.isIn(rows.map((r) => r.id)))
              ..orderBy([OrderingTerm.asc(t.name)]))
            .get();

    final symptoms = <String, List<String>>{};
    final meds = <String, List<String>>{};
    for (final r in tagRows) {
      final tag = r.readTable(t);
      final entryId = r.readTable(et).entryId;
      final bucket = tag.kind == TagKind.symptom ? symptoms : meds;
      bucket.putIfAbsent(entryId, () => []).add(tag.name);
    }
    return [
      for (final r in rows)
        JournalEntry(
          id: r.id,
          createdAt: r.createdAt,
          mood: r.mood,
          sleepHours: r.sleepHours,
          note: r.note,
          fromVoice: r.fromVoice,
          symptoms: symptoms[r.id] ?? const [],
          medications: meds[r.id] ?? const [],
        ),
    ];
  }

  @override
  Future<JournalEntry?> getEntry(String id) async {
    final row = await (_db.select(
      _db.entries,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return (await _withTags([row])).single;
  }

  @override
  Future<void> saveEntry(JournalEntry entry) {
    return _db.transaction(() async {
      await _db
          .into(_db.entries)
          .insertOnConflictUpdate(
            EntriesCompanion.insert(
              id: entry.id,
              createdAt: entry.createdAt,
              updatedAt: _clock(),
              mood: entry.mood,
              sleepHours: Value(entry.sleepHours),
              note: Value(entry.note),
              fromVoice: Value(entry.fromVoice),
            ),
          );
      await (_db.delete(
        _db.entryTags,
      )..where((et) => et.entryId.equals(entry.id))).go();
      final tagged = [
        for (final s in entry.symptoms) (s, TagKind.symptom),
        for (final m in entry.medications) (m, TagKind.medication),
      ];
      for (final (name, kind) in tagged) {
        final tagId = await _tagId(name, kind);
        await _db
            .into(_db.entryTags)
            .insert(
              EntryTagsCompanion.insert(entryId: entry.id, tagId: tagId),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
  }

  /// Case-insensitive lookup so "Headache" and "headache" share one tag.
  Future<int> _tagId(String name, TagKind kind) async {
    final existing =
        await (_db.select(_db.tags)
              ..where(
                (t) =>
                    t.name.lower().equals(name.toLowerCase()) &
                    t.kind.equalsValue(kind),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    return _db
        .into(_db.tags)
        .insert(TagsCompanion.insert(name: name, kind: kind));
  }

  @override
  Future<void> deleteEntry(String id) =>
      (_db.delete(_db.entries)..where((e) => e.id.equals(id))).go();

  @override
  Stream<List<TagUsage>> watchTags(TagKind kind) {
    final t = _db.tags;
    final et = _db.entryTags;
    final uses = et.entryId.count();
    final query =
        _db.selectOnly(t).join([leftOuterJoin(et, et.tagId.equalsExp(t.id))])
          ..addColumns([t.name, uses])
          ..where(t.kind.equalsValue(kind))
          ..groupBy([t.id])
          ..orderBy([OrderingTerm.desc(uses), OrderingTerm.asc(t.name)]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          TagUsage(name: r.read(t.name)!, kind: kind, count: r.read(uses)!),
      ],
    );
  }

  @override
  Future<void> deleteAll() => _db.transaction(() async {
    await _db.delete(_db.entryTags).go();
    await _db.delete(_db.entries).go();
    await _db.delete(_db.tags).go();
  });
}
