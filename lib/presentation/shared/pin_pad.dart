import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mindfull/core/theme.dart';

/// Numeric keypad with PIN dots. No TextField, so it works above the
/// navigator (in the lock overlay) and never shows the system keyboard.
class PinPad extends StatefulWidget {
  const PinPad({
    required this.title,
    required this.onSubmit,
    this.subtitle,
    this.error,
    this.enabled = true,
    this.trailingAction,
    super.key,
  });

  static const minLength = 4;
  static const maxLength = 8;

  final String title;
  final String? subtitle;
  final String? error;
  final bool enabled;

  /// Return true to clear the entered digits (e.g. on rejection).
  final Future<void> Function(String pin) onSubmit;

  /// Shown in the bottom-left key slot, e.g. a biometrics button.
  final Widget? trailingAction;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  void clear() => setState(() => _pin = '');

  void _tap(String d) {
    if (!widget.enabled || _busy || _pin.length >= PinPad.maxLength) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _pin += d);
  }

  void _backspace() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_pin.length < PinPad.minLength || _busy || !widget.enabled) return;
    setState(() => _busy = true);
    final pin = _pin;
    try {
      await widget.onSubmit(pin);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.subtitle!,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        Semantics(
          label: '${_pin.length} digits entered',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < PinPad.maxLength; i++)
                if (i < _pin.length || i < PinPad.minLength)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length
                          ? MindfullTokens.of(context).brand
                          : null,
                      border: Border.all(
                        color: i < _pin.length
                            ? MindfullTokens.of(context).brand
                            : scheme.outline,
                        width: 1.5,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: Center(
            child: widget.error == null
                ? null
                : Text(
                    widget.error!,
                    style: TextStyle(color: scheme.error),
                    textAlign: TextAlign.center,
                  ),
          ),
        ),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in row) _Key(label: d, onTap: () => _tap(d)),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 88,
              height: 80,
              child: Center(child: widget.trailingAction),
            ),
            _Key(label: '0', onTap: () => _tap('0')),
            SizedBox(
              width: 88,
              height: 80,
              child: IconButton(
                tooltip: 'Delete',
                onPressed: _pin.isEmpty ? null : _backspace,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
          onPressed: _pin.length >= PinPad.minLength && !_busy && widget.enabled
              ? _submit
              : null,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = MindfullTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SizedBox.square(
        dimension: 68,
        child: TextButton(
          style: TextButton.styleFrom(
            shape: CircleBorder(side: BorderSide(color: t.cardBorder)),
            backgroundColor: t.chip,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: onTap,
          child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
        ),
      ),
    );
  }
}
