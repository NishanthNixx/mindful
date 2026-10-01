import 'package:flutter/foundation.dart';

@immutable
class StoredEmbedding {
  const StoredEmbedding({
    required this.entryId,
    required this.modelId,
    required this.textHash,
    required this.vector,
  });

  final String entryId;
  final String modelId;

  /// Hash of the text that was embedded; a changed entry gets re-embedded.
  final String textHash;
  final Float32List vector;
}

/// Vectors live in the encrypted journal database, never in a separate
/// plaintext store.
abstract interface class EmbeddingStore {
  Future<void> upsert(StoredEmbedding embedding);

  Future<void> delete(String entryId);

  Future<Map<String, StoredEmbedding>> all(String modelId);

  Future<void> clear();
}
