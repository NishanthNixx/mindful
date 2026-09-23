import 'package:mindfull/domain/ai/model_spec.dart';

/// A piece of streamed model output.
sealed class LlmChunk {
  const LlmChunk();
}

class LlmText extends LlmChunk {
  const LlmText(this.text);

  final String text;
}

/// Hidden reasoning (Qwen3 "thinking"); shown only as a "thinking…" state.
class LlmThinking extends LlmChunk {
  const LlmThinking(this.text);

  final String text;
}

/// One conversation with its own history.
abstract interface class LlmSession {
  /// Streams the reply to [message]. Cancelling the subscription must stop
  /// generation on the native side, not just stop listening.
  Stream<LlmChunk> send(String message);

  /// Tokenizer count for [text] (for tokens/sec metrics); null if unknown.
  Future<int?> countTokens(String text);

  Future<void> close();
}

/// On-device language model. Implemented by `GemmaLlmEngine` and by fakes in
/// tests. The UI never talks to flutter_gemma directly.
abstract interface class LlmEngine {
  /// Loads a verified model file into memory. Heavy; call once.
  Future<void> load(ModelSpec model, String filePath);

  bool get isLoaded;

  Future<LlmSession> openSession({String? systemInstruction});

  Future<void> unload();
}
