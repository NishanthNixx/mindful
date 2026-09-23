import 'package:flutter/foundation.dart';
import 'package:mindfull/domain/ai/model_spec.dart';

@immutable
class DeviceProfile {
  const DeviceProfile({
    required this.totalRamBytes,
    required this.freeDiskBytes,
    required this.model,
    required this.osVersion,
  });

  final int totalRamBytes;
  final int freeDiskBytes;
  final String model;
  final String osVersion;
}

/// Space kept free beyond the model itself, so the phone isn't left full.
const int storageHeadroomBytes = 512 * 1024 * 1024;

sealed class ModelRecommendation {
  const ModelRecommendation();
}

class Recommended extends ModelRecommendation {
  const Recommended(this.model, {required this.fitsStorage});

  final ModelSpec model;

  /// False when the phone has enough memory but not enough free space yet.
  final bool fitsStorage;
}

class NotSupported extends ModelRecommendation {
  const NotSupported(this.reason);

  final String reason;
}

/// Picks the best model this phone's RAM can run. Storage is reported
/// separately because the user can free space; they can't add RAM.
ModelRecommendation recommendModel(
  DeviceProfile device, {
  List<ModelSpec> catalog = ModelCatalog.all,
}) {
  for (final m in catalog) {
    if (device.totalRamBytes >= m.minRamBytes) {
      return Recommended(
        m,
        fitsStorage: fitsStorage(device, m, alreadyDownloaded: 0),
      );
    }
  }
  // Round up to the advertised size ("2.8 GiB" → "3 GB") so it matches the box.
  final gb = (device.totalRamBytes / (1024 * 1024 * 1024) / 0.93).round();
  return NotSupported(
    'This phone has about $gb GB of memory. On-device AI needs at least 3 GB, so it is switched off. '
    'Journaling works exactly the same.',
  );
}

bool fitsStorage(
  DeviceProfile device,
  ModelSpec model, {
  required int alreadyDownloaded,
}) =>
    device.freeDiskBytes >=
    model.sizeBytes - alreadyDownloaded + storageHeadroomBytes;

/// Models this phone can run at all (for "choose a different model").
List<ModelSpec> compatibleModels(
  DeviceProfile device, {
  List<ModelSpec> catalog = ModelCatalog.all,
}) => [
  for (final m in catalog)
    if (device.totalRamBytes >= m.minRamBytes) m,
];
