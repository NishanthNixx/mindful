/// A journal entry matched to a question, with its similarity score.
class RetrievedEntry {
  const RetrievedEntry({required this.entryId, required this.score});

  final String entryId;
  final double score;
}

/// Finds the journal entries most relevant to a query (top-k).
abstract interface class Retriever {
  Future<void> index(String entryId, String text);

  Future<void> remove(String entryId);

  Future<List<RetrievedEntry>> search(String query, {int k = 5});
}
