import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/presentation/shared/mindfull_scaffold.dart';

const _navHeight = 64.0;

class HomeShell extends StatelessWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  static const List<(IconData, IconData, String)> _items = [
    (Icons.auto_stories_outlined, Icons.auto_stories, 'Journal'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Ask'),
    (Icons.shield_outlined, Icons.shield, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final navInset = _navHeight + 12 + (bottomSafe > 0 ? bottomSafe : 12);
    return Stack(
      children: [
        ShellInsets(bottom: navInset, child: shell),
        Positioned(
          left: 16,
          right: 16,
          bottom: bottomSafe > 0 ? bottomSafe : 12,
          // The bar sits outside the branch Scaffolds, so it needs its own
          // Material for ink effects.
          child: Material(
            type: MaterialType.transparency,
            child: _PillNavBar(
              index: shell.currentIndex,
              onTap: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
            ),
          ),
        ),
      ],
    );
  }
}

class _PillNavBar extends StatelessWidget {
  const _PillNavBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final t = MindfullTokens.of(context);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          height: _navHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: t.headerScrim.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: t.cardBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F3D6858),
                blurRadius: 24,
                offset: Offset(0, 8),
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Equal thirds; an item scales down (never truncates) when the
              // screen is narrow or the text size is large.
              for (var i = 0; i < HomeShell._items.length; i++)
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _NavItem(
                        icon: i == index
                            ? HomeShell._items[i].$2
                            : HomeShell._items[i].$1,
                        label: HomeShell._items[i].$3,
                        selected: i == index,
                        onTap: () => onTap(i),
                        selectedColor: t.brand,
                        onSelected: t.onBrand,
                        idle: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
    required this.onSelected,
    required this.idle,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color onSelected;
  final Color idle;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? onSelected : idle;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x2E255041),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
