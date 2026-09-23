import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/repositories/journal_repo.dart';
import 'package:mindfull/domain/usecases/log_entry.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements JournalRepo {}

void main() {
  setUpAll(
    () => registerFallbackValue(
      JournalEntry(id: 'x', createdAt: DateTime(2026), mood: 3),
    ),
  );

  test('trims note and dedupes tags case-insensitively', () async {
    final repo = _MockRepo();
    when(() => repo.saveEntry(any())).thenAnswer((_) async {});

    await LogEntry(repo)(
      JournalEntry(
        id: 'a',
        createdAt: DateTime(2026),
        mood: 3,
        note: '  slept badly \n',
        symptoms: const ['Migraine', ' migraine', '', 'nausea'],
      ),
    );

    final saved =
        verify(() => repo.saveEntry(captureAny())).captured.single
            as JournalEntry;
    expect(saved.note, 'slept badly');
    expect(saved.symptoms, ['Migraine', 'nausea']);
  });
}
