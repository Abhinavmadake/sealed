import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Frosted, translucent surface with a specular rim, in the spirit of Apple's Liquid Glass.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.shape = const StadiumBorder(),
    this.blur = 18,
    this.tint = 0.07,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final ShapeBorder shape;
  final double blur;
  final double tint;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: ShapeBorderClipper(shape: shape),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: CustomPaint(
        foregroundPainter: _RimPainter(shape),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: tint * 2.1),
                Colors.white.withValues(alpha: tint * 0.6),
                Colors.white.withValues(alpha: tint),
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.shape);

  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getInnerPath(rect.deflate(0.5));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.3),
          ],
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );
    final sheen = Rect.fromLTWH(0, 0, size.width, size.height * 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0)],
        ).createShader(sheen),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.shape != shape;
}

/// A tappable glass pill.
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.onPressed, required this.child, this.icon, this.height = 52});

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
      color: onPressed == null ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onSurface,
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Glass(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            customBorder: const StadiumBorder(),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      IconTheme.merge(
                        data: IconThemeData(color: style?.color, size: 20),
                        child: icon!,
                      ),
                      const SizedBox(width: 10),
                    ],
                    DefaultTextStyle.merge(style: style, child: child),
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

/// Page backdrop for root screens: base colour, optional art behind, transparent scaffold on top.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.behind, required this.child});

  final List<Widget> behind;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Stack(
      children: [
        ...behind,
        Positioned.fill(child: child),
      ],
    ),
  );
}
