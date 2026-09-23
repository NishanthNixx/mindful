/// On-device language model. Implemented by `GemmaLlmEngine` (week 2) and by
/// fakes in tests. The UI never talks to flutter_gemma directly.
abstract interface class LlmEngine {
  /// Streams generated text chunks. Cancelling the subscription must stop
  /// generation on the native side, not just stop listening.
  Stream<String> generate(String prompt, {int maxTokens = 512});

  Future<void> dispose();
}
