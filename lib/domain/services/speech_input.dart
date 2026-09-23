/// Speech-to-text boundary. Implementations must recognise on the device only;
/// if that isn't possible they report an error rather than using a server.
abstract interface class SpeechInput {
  /// False when the device can't do on-device recognition or permission was
  /// denied.
  Future<bool> initialize();

  Future<void> start({
    required void Function(String transcript, {required bool isFinal}) onResult,
    required void Function(String message) onError,
  });

  Future<void> stop();

  bool get isListening;
}
