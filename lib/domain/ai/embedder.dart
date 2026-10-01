import 'package:mindfull/domain/ai/model_spec.dart';

enum EmbedPurpose { query, document }

/// Turns text into a vector for local retrieval.
abstract interface class Embedder {
  /// Identifies the vector space; stored with each vector so a model change
  /// triggers re-indexing instead of mixing incompatible vectors.
  String get modelId;

  Future<List<double>> embed(
    String text, {
    EmbedPurpose purpose = EmbedPurpose.query,
  });
}

/// An [Embedder] backed by a model file that must be loaded first.
abstract interface class EmbedderRuntime implements Embedder {
  Future<void> load(
    EmbedderSpec spec, {
    required String modelPath,
    required String tokenizerPath,
  });

  bool get isLoaded;

  Future<void> unload();
}
