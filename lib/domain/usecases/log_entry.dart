import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/repositories/journal_repo.dart';

/// Normalises and saves an entry. Later this also triggers embedding (week 3);
/// the `logEntry` tool for function calling (week 4) goes through here too.
class LogEntry {
  const LogEntry(this._repo);

  final JournalRepo _repo;

  Future<void> call(JournalEntry entry) {
    return _repo.saveEntry(
      entry.copyWith(
        note: entry.note.trim(),
        symptoms: _clean(entry.symptoms),
        medications: _clean(entry.medications),
      ),
    );
  }

  static List<String> _clean(List<String> tags) {
    final seen = <String>{};
    return [
      for (final t in tags.map((t) => t.trim()))
        if (t.isNotEmpty && seen.add(t.toLowerCase())) t,
    ];
  }
}
