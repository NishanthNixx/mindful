import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/data/db/app_database.dart';
import 'package:mindfull/data/db/encrypted_connection.dart';
import 'package:mindfull/data/repositories/drift_journal_repo.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';

const _keyA =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _keyB =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

AppDatabase _open(File f, String key) =>
    AppDatabase(NativeDatabase(f, setup: (db) => applyCipherKey(db, key)));

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mindfull_db_test');
    file = File('${dir.path}/$dbFileName');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('data is not readable as plaintext on disk', () async {
    final db = _open(file, _keyA);
    await DriftJournalRepo(db).saveEntry(
      JournalEntry(
        id: 'e1',
        createdAt: DateTime(2026, 9),
        mood: 2,
        note: 'SECRET-MIGRAINE-NOTE',
        symptoms: const ['migraine'],
      ),
    );
    await db.close();

    final bytes = file.readAsBytesSync();
    expect(
      String.fromCharCodes(bytes.take(16)),
      isNot(startsWith('SQLite format 3')),
    );
    expect(
      String.fromCharCodes(bytes).contains('SECRET-MIGRAINE-NOTE'),
      isFalse,
    );
  });

  test('reopens with the right key, refuses the wrong key', () async {
    final db = _open(file, _keyA);
    await DriftJournalRepo(
      db,
    ).saveEntry(JournalEntry(id: 'e1', createdAt: DateTime(2026, 9), mood: 4));
    await db.close();

    final again = _open(file, _keyA);
    expect(await DriftJournalRepo(again).getEntry('e1'), isNotNull);
    await again.close();

    final wrong = _open(file, _keyB);
    await expectLater(wrong.customSelect('SELECT 1').get(), throwsA(anything));
    await wrong.close();
  });

  test('schema is created with foreign keys on', () async {
    final db = _open(file, _keyA);
    final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(fk.read<int>('foreign_keys'), 1);
    await db.close();
  });
}
