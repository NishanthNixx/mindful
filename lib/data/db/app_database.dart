import 'package:drift/drift.dart';
import 'package:mindfull/domain/entities/tag.dart';

part 'app_database.g.dart';

@DataClassName('EntryRow')
class Entries extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  // Drift's documented pattern for CHECK constraints.
  // ignore: recursive_getters
  IntColumn get mood => integer().check(mood.isBetweenValues(1, 5))();
  RealColumn get sleepHours => real().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get fromVoice => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagRow')
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 64)();
  IntColumn get kind => intEnum<TagKind>()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {name, kind},
  ];
}

@DataClassName('EntryTagRow')
class EntryTags extends Table {
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {entryId, tagId};
}

@DriftDatabase(tables: [Entries, Tags, EntryTags])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await m.createIndex(
        Index(
          'entries_created_at',
          'CREATE INDEX entries_created_at ON entries (created_at)',
        ),
      );
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Overwrite deleted content with zeros instead of leaving it in free pages.
      await customStatement('PRAGMA secure_delete = ON');
    },
  );
}
