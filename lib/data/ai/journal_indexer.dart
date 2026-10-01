import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mindfull/domain/ai/embedder.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';
import 'package:mindfull/domain/journal_search/embedding_store.dart';
import 'package:mindfull/domain/journal_search/retriever.dart';
import 'package:mindfull/domain/repositories/journal_repo.dart';

@immutable
class IndexProgress {
  const IndexProgress({
    required this.done,
    required this.total,
    this.running = false,
  });

  final int done;
  final int total;
  final bool running;

  static const idle = IndexProgress(done: 0, total: 0);
}

/// Keeps one vector per entry in step with the journal. Idempotent: only
/// entries that are new, edited (text hash changed) or embedded with another
/// model are (re-)embedded.
class JournalIndexer extends ValueNotifier<IndexProgress> {
  JournalIndexer({required this.repo, required this.store})
    : super(IndexProgress.idle);

  final JournalRepo repo;
  final EmbeddingStore store;
  Future<int>? _running;

  static String hashOf(JournalEntry e) =>
      sha256.convert(embeddingText(e).codeUnits).toString();

  /// Embeds everything that's missing or stale. Returns how many were embedded.
  Future<int> sync(Embedder embedder) =>
      _running ??= _sync(embedder).whenComplete(() => _running = null);

  Future<int> _sync(Embedder embedder) async {
    final entries = await repo.entries();
    final existing = await store.all(embedder.modelId);
    final stale = [
      for (final e in entries)
        if (existing[e.id]?.textHash != hashOf(e)) e,
    ];
    value = IndexProgress(
      done: 0,
      total: stale.length,
      running: stale.isNotEmpty,
    );
    var done = 0;
    for (final e in stale) {
      await index(embedder, e);
      value = IndexProgress(
        done: ++done,
        total: stale.length,
        running: done < stale.length,
      );
    }
    return done;
  }

  Future<void> index(Embedder embedder, JournalEntry e) async {
    final vector = await embedder.embed(
      embeddingText(e),
      purpose: EmbedPurpose.document,
    );
    await store.upsert(
      StoredEmbedding(
        entryId: e.id,
        modelId: embedder.modelId,
        textHash: hashOf(e),
        vector: Float32List.fromList(vector),
      ),
    );
  }
}
