import 'package:flutter/services.dart';
import 'package:mindfull/domain/ai/device_profile.dart';
import 'package:mindfull/domain/services/device_info.dart';

/// Backed by the `mindfull/device` channel in AppDelegate.swift / MainActivity.kt.
class PlatformDeviceInfo implements DeviceInfoSource {
  const PlatformDeviceInfo();

  static const _channel = MethodChannel('mindfull/device');

  @override
  Future<DeviceProfile> profile() async {
    final m =
        await _channel.invokeMapMethod<String, Object?>('profile') ?? const {};
    return DeviceProfile(
      totalRamBytes: (m['totalRamBytes'] as num?)?.toInt() ?? 0,
      freeDiskBytes: (m['freeDiskBytes'] as num?)?.toInt() ?? 0,
      model: m['model'] as String? ?? 'Unknown device',
      osVersion: m['osVersion'] as String? ?? '',
    );
  }

  @override
  Future<void> excludeFromBackup(String path) =>
      _channel.invokeMethod<bool>('excludeFromBackup', {'path': path});
}
