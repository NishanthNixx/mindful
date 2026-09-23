import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/presentation/shared/appearance.dart';

const _headerHeight = 64.0;

/// Space the floating pill nav bar occupies; set by HomeShell so tab screens
/// can pad their scroll content. Zero outside the shell.
class ShellInsets extends InheritedWidget {
  const ShellInsets({required this.bottom, required super.child, super.key});

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellInsets>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(ShellInsets old) => old.bottom != bottom;
}

class Emblem extends StatelessWidget {
  const Emblem({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Image.asset(
        'assets/images/emblem.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'Mindfull',
      ),
    );
  }
}

/// Page frame shared by every screen: optional nature backdrop, frosted header
/// with emblem + "MINDFULL" overline + serif title, and content padding that
/// clears the header and the floating nav.
class MindfullScaffold extends ConsumerWidget {
  const MindfullScaffold({
    required this.title,
    required this.scene,
    required this.body,
    this.leading,
    this.actions = const [],
    this.showOverline = true,
    this.floatingActionButton,
    super.key,
  });

  final String title;
  final Scene scene;

  /// Built with the insets its scroll view should use.
  final Widget Function(BuildContext context, EdgeInsets padding) body;
  final Widget? leading;
  final List<Widget> actions;
  final bool showOverline;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nature = ref.watch(natureBackgroundsProvider);
    final media = MediaQuery.of(context);
    final navInset = ShellInsets.bottomOf(context);
    final padding = EdgeInsets.fromLTRB(
      20,
      media.padding.top + _headerHeight + 8,
      20,
      (navInset > 0 ? navInset : media.padding.bottom) + 24,
    );

    return Scaffold(
      backgroundColor: MindfullTokens.of(context).canvas,
      extendBodyBehindAppBar: true,
      extendBody: true,
      resizeToAvoidBottomInset: true,
      floatingActionButton: floatingActionButton == null
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: navInset),
              child: floatingActionButton,
            ),
      appBar: _Header(
        title: title,
        leading: leading,
        actions: actions,
        showOverline: showOverline,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (nature) _NatureBackdrop(scene: scene),
          Builder(builder: (context) => body(context, padding)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget implements PreferredSizeWidget {
  const _Header({
    required this.title,
    required this.actions,
    required this.showOverline,
    this.leading,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final bool showOverline;

  @override
  Size get preferredSize => const Size.fromHeight(_headerHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = MindfullTokens.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: t.headerScrim,
            border: Border(bottom: BorderSide(color: t.cardBorder)),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _headerHeight,
              child: Padding(
                padding: EdgeInsets.only(
                  left: leading == null ? 20 : 4,
                  right: 12,
                ),
                child: Row(
                  children: [
                    ?leading,
                    const Emblem(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showOverline)
                            Text(
                              'MINDFULL',
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.4,
                                height: 1.2,
                              ),
                            ),
                          Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft-focus photo with a parchment (or night) wash so text stays legible.
/// No per-card blur: cards are simply translucent, which keeps budget phones
/// at 60fps.
class _NatureBackdrop extends StatelessWidget {
  const _NatureBackdrop({required this.scene});

  final Scene scene;

  @override
  Widget build(BuildContext context) {
    final canvas = MindfullTokens.of(context).canvas;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            scene.asset,
            fit: BoxFit.cover,
            opacity: AlwaysStoppedAnimation(dark ? 0.35 : 0.6),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  canvas.withValues(alpha: dark ? 0.7 : 0.4),
                  canvas.withValues(alpha: dark ? 0.45 : 0),
                  canvas.withValues(alpha: dark ? 0.8 : 0.6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
