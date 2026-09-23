import 'package:mindfull/domain/ai/model_spec.dart';

/// Lifecycle of the on-device model. AI features read this and render a clear
/// "not ready" state instead of failing.
sealed class ModelStatus {
  const ModelStatus();
}

class ModelNotInstalled extends ModelStatus {
  const ModelNotInstalled();
}

class ModelDownloading extends ModelStatus {
  const ModelDownloading({
    required this.model,
    required this.receivedBytes,
    required this.totalBytes,
    this.bytesPerSecond = 0,
    this.paused = false,
  });

  final ModelSpec model;
  final int receivedBytes;
  final int totalBytes;
  final double bytesPerSecond;

  /// Paused by the user, or interrupted (app killed, network lost). Resumes
  /// from [receivedBytes].
  final bool paused;

  double get progress => totalBytes == 0 ? 0 : receivedBytes / totalBytes;
}

class ModelVerifying extends ModelStatus {
  const ModelVerifying({required this.model, required this.progress});

  final ModelSpec model;
  final double progress;
}

/// Verified file on disk, not loaded yet. Loading waits until the user opens
/// Ask, so journaling-only launches stay fast and light on memory.
class ModelInstalled extends ModelStatus {
  const ModelInstalled(this.model);

  final ModelSpec model;
}

/// Verified file on disk; being loaded into memory.
class ModelLoading extends ModelStatus {
  const ModelLoading(this.model);

  final ModelSpec model;
}

class ModelReady extends ModelStatus {
  const ModelReady(this.model);

  final ModelSpec model;
}

class ModelFailed extends ModelStatus {
  const ModelFailed({
    required this.message,
    this.model,
    this.canResume = false,
  });

  final String message;
  final ModelSpec? model;
  final bool canResume;
}

/// The device can't run any supported model (e.g. too little RAM). AI features
/// are switched off cleanly.
class ModelUnsupported extends ModelStatus {
  const ModelUnsupported(this.reason);

  final String reason;
}
