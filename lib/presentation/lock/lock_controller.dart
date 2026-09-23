import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';

enum AppLockState { checking, locked, unlocked }

/// Decides when the lock screen shows: on cold start, and on resume after the
/// app has been in the background longer than [grace].
class LockController extends Notifier<AppLockState> {
  static const grace = Duration(seconds: 30);

  DateTime? _backgroundedAt;

  @override
  AppLockState build() {
    unawaited(Future.microtask(_init));
    return AppLockState.checking;
  }

  Future<void> _init() async {
    final enabled = await ref.read(appLockServiceProvider).isEnabled();
    state = enabled ? AppLockState.locked : AppLockState.unlocked;
  }

  void onBackgrounded() => _backgroundedAt ??= DateTime.now();

  Future<void> onResumed() async {
    final at = _backgroundedAt;
    _backgroundedAt = null;
    if (at == null || state != AppLockState.unlocked) return;
    if (DateTime.now().difference(at) >= grace &&
        await ref.read(appLockServiceProvider).isEnabled()) {
      state = AppLockState.locked;
    }
  }

  void unlock() => state = AppLockState.unlocked;

  void lockNow() => state = AppLockState.locked;
}

final lockControllerProvider = NotifierProvider<LockController, AppLockState>(
  LockController.new,
);
