import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';

final lockEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(appLockServiceProvider).isEnabled(),
);

final biometricsAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(appLockServiceProvider).biometricsAvailable(),
);

final biometricsEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(appLockServiceProvider).biometricsEnabled(),
);

void refreshLockSettings(WidgetRef ref) => ref
  ..invalidate(lockEnabledProvider)
  ..invalidate(biometricsEnabledProvider);
