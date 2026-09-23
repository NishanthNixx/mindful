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
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double get progress => totalBytes == 0 ? 0 : receivedBytes / totalBytes;
}

class ModelReady extends ModelStatus {
  const ModelReady({required this.modelId});

  final String modelId;
}

/// The device can't run any supported model (e.g. too little RAM). AI features
/// are switched off cleanly.
class ModelUnsupported extends ModelStatus {
  const ModelUnsupported(this.reason);

  final String reason;
}
