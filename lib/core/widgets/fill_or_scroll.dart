import 'package:flutter/material.dart';

/// Lays a column out full-height when there is room, and scrolls it when
/// there is not — which is what happens the moment the keyboard appears on a
/// small phone.
///
/// Screens that pin a CTA to the bottom with `Spacer` need this: a bare
/// Column simply overflows once the viewport shrinks. Do not add
/// `viewInsets.bottom` padding on top of it — the Scaffold already resizes
/// the body, and adding the inset again double-counts it.
class FillOrScroll extends StatelessWidget {
  const FillOrScroll({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - padding.vertical,
            ),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}
