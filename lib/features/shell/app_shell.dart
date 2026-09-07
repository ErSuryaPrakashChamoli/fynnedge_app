import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';

/// Bottom navigation host for the five persistent destinations.
/// Everything else in the app pushes on top of this.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = <(String, IconData, IconData)>[
    ('Home', Icons.dashboard_outlined, Icons.dashboard_rounded),
    ('Explore', Icons.explore_outlined, Icons.explore_rounded),
    ('FynnAI', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
    ('Activity', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
    ('Profile', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgElevated,
          border: Border(top: BorderSide(color: AppColors.borderSoft)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _NavItem(
                      label: _items[i].$1,
                      icon: _items[i].$2,
                      activeIcon: _items[i].$3,
                      selected: navigationShell.currentIndex == i,
                      isAi: i == 2,
                      onTap: () => navigationShell.goBranch(
                        i,
                        initialLocation: i == navigationShell.currentIndex,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
    this.isAi = false,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;
  final bool isAi;

  @override
  Widget build(BuildContext context) {
    final accent = isAi ? AppColors.violet : AppColors.mint;
    final color = selected ? accent : AppColors.textTertiary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // A short accent bar marks the active tab without shifting layout.
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            height: 2.5,
            width: selected ? 20 : 0,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 9),
          Icon(selected ? activeIcon : icon, size: 21, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
