import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';
import 'package:mindfull/data/security/app_lock_service.dart';
import 'package:mindfull/presentation/settings/lock_settings_providers.dart';
import 'package:mindfull/presentation/shared/appearance.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart';
import 'package:mindfull/presentation/shared/paper_card.dart';
import 'package:mindfull/presentation/shared/pin_pad.dart';

enum _Step { overview, verifyCurrent, enterNew, confirmNew }

enum LockSetupAction { change, disable }

class AppLockSetupScreen extends ConsumerStatefulWidget {
  const AppLockSetupScreen({this.initialAction, super.key});

  /// Jump straight to verifying the current PIN for this action.
  final LockSetupAction? initialAction;

  @override
  ConsumerState<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

class _AppLockSetupScreenState extends ConsumerState<AppLockSetupScreen> {
  _Step? _step;
  LockSetupAction? _action;
  String? _firstPin;
  String? _error;

  AppLockService get _service => ref.read(appLockServiceProvider);

  @override
  void initState() {
    super.initState();
    if (widget.initialAction case final action?) {
      _action = action;
      _step = _Step.verifyCurrent;
    }
  }

  /// Until the user picks an action, the step follows whether a lock exists.
  _Step get _currentStep =>
      _step ??
      (ref.read(lockEnabledProvider).value ?? false
          ? _Step.overview
          : _Step.enterNew);

  void _go(_Step step, {String? error}) => setState(() {
    _step = step;
    _error = error;
  });

  Future<void> _onPin(String pin) async {
    switch (_currentStep) {
      case _Step.verifyCurrent:
        switch (await _service.verifyPin(pin)) {
          case PinAccepted():
            if (_action == LockSetupAction.disable) {
              await _service.disable();
              _done('App lock turned off');
            } else {
              _go(_Step.enterNew);
            }
          case PinRejected(:final attemptsLeft):
            _go(_Step.verifyCurrent, error: 'Wrong PIN. $attemptsLeft left.');
          case PinLockedOut():
            _go(
              _Step.verifyCurrent,
              error: 'Too many attempts. Try again later.',
            );
        }
      case _Step.enterNew:
        _firstPin = pin;
        _go(_Step.confirmNew);
      case _Step.confirmNew:
        if (pin != _firstPin) {
          _firstPin = null;
          _go(_Step.enterNew, error: "PINs didn't match. Try again.");
          return;
        }
        await _service.enable(
          pin,
          useBiometrics: await _service.biometricsAvailable(),
        );
        _done('App lock is on');
      case _Step.overview:
        break;
    }
  }

  void _done(String message) {
    refreshLockSettings(ref);
    // Settings shows the message in its own tab once we're gone.
    if (mounted) Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(lockEnabledProvider);
    final step = _currentStep;

    return MindfullScaffold(
      title: 'App lock',
      scene: Scene.settings,
      showOverline: false,
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
      ),
      body: (context, padding) => enabled.isLoading
          ? const Center(child: CircularProgressIndicator())
          : step == _Step.overview
          ? ListView(
              padding: padding,
              children: [
                PaperCard(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.check_circle_outline),
                        title: Text('App lock is on'),
                        subtitle: Text(
                          'Mindfull locks on launch and after 30 seconds in the background.',
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.pin_outlined),
                        title: const Text('Change PIN'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          _action = LockSetupAction.change;
                          _go(_Step.verifyCurrent);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.lock_open_outlined),
                        title: const Text('Turn off app lock'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          _action = LockSetupAction.disable;
                          _go(_Step.verifyCurrent);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            )
          : SingleChildScrollView(
              padding: padding,
              child: PaperCard(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
                child: PinPad(
                  key: ValueKey(step),
                  title: switch (step) {
                    _Step.verifyCurrent => 'Enter your current PIN',
                    _Step.enterNew => 'Choose a PIN',
                    _Step.confirmNew => 'Confirm your PIN',
                    _Step.overview => '',
                  },
                  subtitle: step == _Step.enterNew
                      ? '${PinPad.minLength}–${PinPad.maxLength} digits'
                      : null,
                  error: _error,
                  onSubmit: _onPin,
                ),
              ),
            ),
    );
  }
}
