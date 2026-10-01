import 'package:flutter_gemma/flutter_gemma.dart' hide ModelSpec;
import 'package:mindfull/data/ai/gemma_init.dart';
import 'package:mindfull/domain/ai/embedder.dart';
import 'package:mindfull/domain/ai/model_spec.dart';

/// Gecko embeddings via flutter_gemma. Only the embedder is used — vectors
/// are stored in Mindfull's own encrypted database, not flutter_gemma's
/// vector store (which would keep a plaintext copy of every entry).
class GemmaEmbedder implements EmbedderRuntime {
  EmbeddingModel? _model;
  String _modelId = '';

  @override
  String get modelId => _modelId;

  @override
  bool get isLoaded => _model != null;

  @override
  Future<void> load(
    EmbedderSpec spec, {
    required String modelPath,
    required String tokenizerPath,
  }) async {
    await ensureGemmaInitialized();
    await unload();
    await FlutterGemma.installEmbedder()
        .modelFromFile(modelPath)
        .tokenizerFromFile(tokenizerPath)
        .install();
    _model = await FlutterGemma.getActiveEmbedder(
      preferredBackend: PreferredBackend.cpu,
    );
    _modelId = spec.id;
  }

  @override
  Future<List<double>> embed(
    String text, {
    EmbedPurpose purpose = EmbedPurpose.query,
  }) {
    final model = _model;
    if (model == null) throw StateError('Embedder not loaded');
    return model.generateEmbedding(
      text,
      taskType: purpose == EmbedPurpose.document
          ? TaskType.retrievalDocument
          : TaskType.retrievalQuery,
    );
  }

  @override
  Future<void> unload() async {
    final model = _model;
    _model = null;
    await model?.close();
  }
}
