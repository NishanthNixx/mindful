import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/presentation/lock/lock_controller.dart';
import 'package:mindfull/presentation/lock/lock_screen.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart'
    show Emblem;

/// Sits above the router. Covers the app with the lock screen when locked, and
/// with a blur whenever the app isn't in the foreground so the app-switcher
/// snapshot never shows journal content. (Android additionally sets
/// FLAG_SECURE in MainActivity.)
class LockGate extends ConsumerStatefulWidget {
  const LockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(lockControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(lock.onResumed());
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        lock.onBackgrounded();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
    setState(() => _obscured = state != AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(lockControllerProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the app tree alive (and its state) underneath the lock.
        ExcludeSemantics(
          excluding: lock != AppLockState.unlocked,
          child: TickerMode(
            enabled: lock == AppLockState.unlocked,
            child: widget.child,
          ),
        ),
        if (lock == AppLockState.checking)
          ColoredBox(color: MindfullTokens.of(context).canvas),
        // Above the router's Navigator, so it needs its own Overlay for tooltips.
        if (lock == AppLockState.locked)
          Overlay.wrap(child: const LockScreen()),
        if (_obscured) const _PrivacyShield(),
      ],
    );
  }
}

class _PrivacyShield extends StatelessWidget {
  const _PrivacyShield() : super(key: const ValueKey('privacy-shield'));

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: ColoredBox(
        color: MindfullTokens.of(context).canvas.withValues(alpha: 0.9),
        child: const Center(child: Emblem(size: 72)),
      ),
    );
  }
}
