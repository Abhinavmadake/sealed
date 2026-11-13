import 'package:flutter/material.dart';

/// Renders [child] at [scale] times its normal size: text, icons, spacing and touch targets together.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = scale;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth / s, h = box.maxHeight / s;
      return Transform.scale(
        scale: s,
        alignment: Alignment.topLeft,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: w,
          maxWidth: w,
          minHeight: h,
          maxHeight: h,
          child: MediaQuery(
            data: mq.copyWith(
              size: mq.size / s,
              padding: mq.padding / s,
              viewPadding: mq.viewPadding / s,
              viewInsets: mq.viewInsets / s,
              systemGestureInsets: mq.systemGestureInsets / s,
            ),
            child: child,
          ),
        ),
      );
    });
  }
}
