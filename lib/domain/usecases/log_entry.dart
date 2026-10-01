import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/repositories/journal_repo.dart';

/// Normalises and saves an entry. Later this also triggers embedding (week 3);
/// the `logEntry` tool for function calling (week 4) goes through here too.
class LogEntry {
  const LogEntry(this._repo, {this.afterSave});

  final JournalRepo _repo;

  /// Runs after a successful save (e.g. embed the entry for search). Its
  /// failures never fail the save.
  final Future<void> Function(JournalEntry saved)? afterSave;

  Future<void> call(JournalEntry entry) async {
    final clean = entry.copyWith(
      note: entry.note.trim(),
      symptoms: _clean(entry.symptoms),
      medications: _clean(entry.medications),
    );
    await _repo.saveEntry(clean);
    await afterSave?.call(clean);
  }

  static List<String> _clean(List<String> tags) {
    final seen = <String>{};
    return [
      for (final t in tags.map((t) => t.trim()))
        if (t.isNotEmpty && seen.add(t.toLowerCase())) t,
    ];
  }
}
