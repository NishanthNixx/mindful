import 'package:flutter_gemma/flutter_gemma.dart' hide ModelSpec;

bool _initialized = false;

/// flutter_gemma's service registry must be initialised once per process.
Future<void> ensureGemmaInitialized() async {
  if (_initialized) return;
  await FlutterGemma.initialize();
  _initialized = true;
}
