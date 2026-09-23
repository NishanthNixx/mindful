import 'package:mindfull/domain/entities/entry_filter.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/entities/tag.dart';

/// Persistence boundary for journal data. The UI and use cases depend on this,
/// never on drift directly.
abstract interface class JournalRepo {
  /// Newest first.
  Stream<List<JournalEntry>> watchEntries([
    EntryFilter filter = const EntryFilter(),
  ]);

  Future<JournalEntry?> getEntry(String id);

  /// Insert or replace.
  Future<void> saveEntry(JournalEntry entry);

  Future<void> deleteEntry(String id);

  /// Known tags ordered by usage, for quick-pick chips.
  Stream<List<TagUsage>> watchTags(TagKind kind);

  /// Wipes every entry and tag. Used by "Delete all my data".
  Future<void> deleteAll();
}
