import 'package:mindfull/domain/services/speech_input.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

class DeviceSpeechInput implements SpeechInput {
  DeviceSpeechInput([SpeechToText? stt]) : _stt = stt ?? SpeechToText();

  final SpeechToText _stt;
  void Function(String message)? _onError;
  bool _ready = false;

  @override
  bool get isListening => _stt.isListening;

  @override
  Future<bool> initialize() async {
    if (_ready) return true;
    return _ready = await _stt.initialize(onError: _handleError);
  }

  void _handleError(SpeechRecognitionError e) {
    // Most commonly "error_language_unavailable" / "error_server" when the
    // on-device model for the locale isn't installed. We never retry online.
    _onError?.call(
      e.errorMsg.contains('no_match') || e.errorMsg.contains('speech_timeout')
          ? "Didn't catch that. Try again."
          : "On-device speech recognition isn't available for this language. Nothing was sent anywhere.",
    );
  }

  @override
  Future<void> start({
    required void Function(String transcript, {required bool isFinal}) onResult,
    required void Function(String message) onError,
  }) async {
    _onError = onError;
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, isFinal: r.finalResult),
      listenOptions: SpeechListenOptions(
        onDevice: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();
}
