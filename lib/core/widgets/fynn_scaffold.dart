import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'ambient_background.dart';
import 'labeled_field.dart';

/// Standard page chrome: ambient canvas + optional lightweight header.
/// Screens supply their own scroll view so each can have its own rhythm.
class FynnScaffold extends StatelessWidget {
  const FynnScaffold({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.showBack = true,
    this.onBack,
    this.bottomBar,
    this.floatingActionButton,
    this.padHorizontal = true,
    this.glowPrimary = AppColors.mint,
    this.glowSecondary = AppColors.blue,
    this.glowIntensity = 1.0,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final bool padHorizontal;
  final Color glowPrimary;
  final Color glowSecondary;
  final double glowIntensity;

  static const EdgeInsets gutter = EdgeInsets.symmetric(horizontal: 20);

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || showBack || actions != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      floatingActionButton: floatingActionButton,
      body: AmbientBackground(
        primary: glowPrimary,
        secondary: glowSecondary,
        intensity: glowIntensity,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (hasHeader)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: _Header(
                    title: title,
                    subtitle: subtitle,
                    actions: actions,
                    showBack: showBack,
                    onBack: onBack,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: padHorizontal ? gutter : EdgeInsets.zero,
                  child: bottomBar == null
                      ? child
                      // Content scrolling under a bottom bar gets sliced
                      // mid-word; a short fade reads as "there is more".
                      : ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.94, 1.0],
                          ).createShader(bounds),
                          blendMode: BlendMode.dstIn,
                          child: child,
                        ),
                ),
              ),
              if (bottomBar != null)
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    12 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.bgElevated,
                    border: Border(
                      top: BorderSide(color: AppColors.borderSoft),
                    ),
                  ),
                  child: bottomBar,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    this.title,
    this.subtitle,
    this.actions,
    required this.showBack,
    this.onBack,
  });

  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        if (showBack && Navigator.of(context).canPop())
          CircleBackButton(onPressed: onBack)
        else
          const SizedBox(width: 8),
        const SizedBox(width: 4),
        Expanded(
          child: title == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title!, style: t.titleLarge),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: t.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
        ),
        ...?actions,
        const SizedBox(width: 4),
      ],
    );
  }
}
