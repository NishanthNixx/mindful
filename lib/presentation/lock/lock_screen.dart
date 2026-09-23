import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/data/security/app_lock_service.dart';
import 'package:mindfull/presentation/lock/lock_controller.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart'
    show Emblem;
import 'package:mindfull/presentation/shared/pin_pad.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _error;
  DateTime? _lockedOutUntil;
  bool _biometrics = false;
  Timer? _ticker;

  AppLockService get _service => ref.read(appLockServiceProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_setup());
  }

  Future<void> _setup() async {
    final bio =
        await _service.biometricsEnabled() &&
        await _service.biometricsAvailable();
    final until = await _service.lockedOutUntil();
    if (!mounted) return;
    setState(() => _biometrics = bio);
    if (until != null) _startLockout(until);
    if (bio && until == null) await _tryBiometrics();
  }

  Future<void> _tryBiometrics() async {
    if (await _service.authenticateWithBiometrics()) {
      ref.read(lockControllerProvider.notifier).unlock();
    }
  }

  void _startLockout(DateTime until) {
    _ticker?.cancel();
    setState(() => _lockedOutUntil = until);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().isAfter(until)) {
        _ticker?.cancel();
        setState(() {
          _lockedOutUntil = null;
          _error = null;
        });
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _submit(String pin) async {
    switch (await _service.verifyPin(pin)) {
      case PinAccepted():
        ref.read(lockControllerProvider.notifier).unlock();
      case PinRejected(:final attemptsLeft):
        setState(
          () => _error =
              'Wrong PIN. $attemptsLeft ${attemptsLeft == 1 ? 'try' : 'tries'} left.',
        );
      case PinLockedOut(:final until):
        _startLockout(until);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final until = _lockedOutUntil;
    final remaining = until?.difference(DateTime.now());
    return Material(
      color: MindfullTokens.of(context).canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Emblem(size: 56),
                const SizedBox(height: 20),
                PinPad(
                  title: 'Mindfull is locked',
                  subtitle: 'Enter your PIN',
                  enabled: until == null,
                  error: remaining != null
                      ? 'Too many attempts. Try again in ${_format(remaining)}.'
                      : _error,
                  onSubmit: _submit,
                  trailingAction: _biometrics && until == null
                      ? IconButton(
                          tooltip: 'Unlock with biometrics',
                          iconSize: 32,
                          onPressed: _tryBiometrics,
                          icon: Icon(
                            Icons.fingerprint,
                            color: MindfullTokens.of(context).brand,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final s = d.inSeconds + 1;
    return s < 60
        ? '${s}s'
        : DateFormat('m:ss').format(DateTime(0).add(Duration(seconds: s)));
  }
}
