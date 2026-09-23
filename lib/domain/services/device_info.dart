import 'package:mindfull/domain/ai/device_profile.dart';

abstract interface class DeviceInfoSource {
  Future<DeviceProfile> profile();

  /// Keeps multi-GB model files out of iCloud backups.
  Future<void> excludeFromBackup(String path);
}
