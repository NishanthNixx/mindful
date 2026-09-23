String formatBytes(num bytes) {
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(bytes >= 10 * gb ? 0 : 1)} GB';
  }
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).round()} KB';
}

String? formatEta(int remainingBytes, double bytesPerSecond) {
  if (bytesPerSecond < 1) return null;
  final seconds = (remainingBytes / bytesPerSecond).round();
  if (seconds < 60) return 'under a minute left';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '~$minutes min left';
  return '~${(minutes / 60).toStringAsFixed(1)} h left';
}
