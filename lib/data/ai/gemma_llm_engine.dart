import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide ModelSpec;
import 'package:mindfull/data/ai/gemma_init.dart';
import 'package:mindfull/domain/ai/llm_engine.dart';
import 'package:mindfull/domain/ai/model_spec.dart';

/// [LlmEngine] on flutter_gemma (LiteRT-LM). The verified file is registered
/// in place (`fromFile`), never copied.
class GemmaLlmEngine implements LlmEngine {
  InferenceModel? _model;
  ModelSpec? _spec;

  @override
  bool get isLoaded => _model != null;

  ModelType _type(ModelSpec m) => switch (m.family) {
    ModelFamily.gemma4 => ModelType.gemma4,
    ModelFamily.qwen3 => ModelType.qwen3,
  };

  @override
  Future<void> load(ModelSpec model, String filePath) async {
    await ensureGemmaInitialized();
    await unload();
    await FlutterGemma.installModel(
      modelType: _type(model),
      fileType: ModelFileType.litertlm,
    ).fromFile(filePath).install();
    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: model.contextTokens,
        preferredBackend: model.useGpu
            ? PreferredBackend.gpu
            : PreferredBackend.cpu,
      );
    } on Object catch (e) {
      if (!model.useGpu) rethrow;
      // Some GPUs/simulators can't run the model; CPU is slower but works.
      debugPrint('GPU backend failed ($e); falling back to CPU');
      _model = await FlutterGemma.getActiveModel(
        maxTokens: model.contextTokens,
        preferredBackend: PreferredBackend.cpu,
      );
    }
    _spec = model;
  }

  @override
  Future<LlmSession> openSession({String? systemInstruction}) async {
    final model = _model;
    final spec = _spec;
    if (model == null || spec == null) throw StateError('Model not loaded');
    final chat = await model.createChat(
      temperature: spec.temperature,
      topK: spec.topK,
      topP: spec.topP,
      isThinking: spec.thinking,
      modelType: _type(spec),
      systemInstruction: systemInstruction,
    );
    return _GemmaSession(chat);
  }

  @override
  Future<void> unload() async {
    final model = _model;
    _model = null;
    _spec = null;
    await model?.close();
  }
}

class _GemmaSession implements LlmSession {
  _GemmaSession(this._chat);

  final InferenceChat _chat;

  @override
  Stream<LlmChunk> send(String message) {
    late StreamController<LlmChunk> controller;
    StreamSubscription<ModelResponse>? sub;
    var finished = false;

    controller = StreamController<LlmChunk>(
      onListen: () async {
        try {
          await _chat.addQueryChunk(Message.text(text: message, isUser: true));
          sub = _chat.generateChatResponseAsync().listen(
            (r) {
              switch (r) {
                case TextResponse(:final token):
                  controller.add(LlmText(token));
                case ThinkingResponse(:final content):
                  controller.add(LlmThinking(content));
                case FunctionCallResponse() || ParallelFunctionCallResponse():
                  break; // Tools arrive in week 4.
              }
            },
            onError: controller.addError,
            onDone: () {
              finished = true;
              unawaited(controller.close());
            },
          );
        } on Object catch (e, st) {
          controller.addError(e, st);
          await controller.close();
        }
      },
      onCancel: () async {
        // The Stop button: halt generation natively, not just stop listening.
        if (!finished) await _chat.stopGeneration();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<int?> countTokens(String text) async {
    try {
      return await _chat.session.sizeInTokens(text);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> close() => _chat.close();
}
