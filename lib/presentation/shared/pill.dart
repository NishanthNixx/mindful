import 'package:flutter/material.dart';
import 'package:mindfull/core/theme.dart';

/// Small rounded badge: icon + label on a soft wash.
class Pill extends StatelessWidget {
  const Pill({
    required this.label,
    this.icon,
    this.background,
    this.foreground,
    this.dense = false,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;
  final bool dense;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = foreground ?? theme.colorScheme.onSurfaceVariant;
    final style =
        (dense ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
            ?.copyWith(color: fg);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 10 : 12,
          vertical: dense ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: background ?? MindfullTokens.of(context).chip,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: dense ? 14 : 17, color: fg),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(label, style: style, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
