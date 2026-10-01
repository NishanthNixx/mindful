import 'dart:typed_data';

import 'package:mindfull/data/db/app_database.dart';
import 'package:mindfull/domain/journal_search/embedding_store.dart';

class DriftEmbeddingStore implements EmbeddingStore {
  DriftEmbeddingStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> upsert(StoredEmbedding e) => _db
      .into(_db.entryEmbeddings)
      .insertOnConflictUpdate(
        EntryEmbeddingsCompanion.insert(
          entryId: e.entryId,
          modelId: e.modelId,
          textHash: e.textHash,
          vector: e.vector.buffer.asUint8List(
            e.vector.offsetInBytes,
            e.vector.lengthInBytes,
          ),
        ),
      );

  @override
  Future<void> delete(String entryId) => (_db.delete(
    _db.entryEmbeddings,
  )..where((t) => t.entryId.equals(entryId))).go();

  @override
  Future<Map<String, StoredEmbedding>> all(String modelId) async {
    final rows = await (_db.select(
      _db.entryEmbeddings,
    )..where((t) => t.modelId.equals(modelId))).get();
    return {
      for (final r in rows)
        r.entryId: StoredEmbedding(
          entryId: r.entryId,
          modelId: r.modelId,
          textHash: r.textHash,
          // Copy into an aligned buffer; blob bytes may not be 4-byte aligned.
          vector: Float32List.view(Uint8List.fromList(r.vector).buffer),
        ),
    };
  }

  @override
  Future<void> clear() => _db.delete(_db.entryEmbeddings).go();
}
