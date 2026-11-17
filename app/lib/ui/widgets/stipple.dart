import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass.dart';
import 'raster.dart';

/// Fine graphite grain laid over every screen.
class GrainOverlay extends StatelessWidget {
  const GrainOverlay({super.key, this.density = 0.03});

  final double density;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _GrainPainter(
            scheme.onSurface.withValues(alpha: dark ? 0.07 : 0.09),
            density,
            MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.color, this.density, this.dpr);

  final Color color;
  final double density;
  final double dpr;

  static final _images = RasterCache(2);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final image = _images.get((size, color, density, dpr), size, dpr, (c) => _draw(c, size));
    drawRaster(canvas, image, Offset.zero & size);
  }

  void _draw(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final n = (size.width * size.height * density).round();
    final fine = Float32List(n * 2);
    final coarse = Float32List((n ~/ 12) * 2);
    for (var i = 0; i < fine.length; i += 2) {
      fine[i] = rng.nextDouble() * size.width;
      fine[i + 1] = rng.nextDouble() * size.height;
    }
    for (var i = 0; i < coarse.length; i += 2) {
      coarse[i] = rng.nextDouble() * size.width;
      coarse[i + 1] = rng.nextDouble() * size.height;
    }
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.square
      ..strokeWidth = 0.9;
    canvas.drawRawPoints(ui.PointMode.points, fine, paint);
    canvas.drawRawPoints(ui.PointMode.points, coarse, paint..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.color != color || old.density != density || old.dpr != dpr;
}

/// A round speckled monogram used for vault items.
class SpeckleDisc extends StatelessWidget {
  const SpeckleDisc({super.key, required this.seed, this.child, this.size = 42});

  final String seed;
  final Widget? child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _DiscPainter(seed.hashCode, scheme.onSurface),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  _DiscPainter(this.seed, this.ink);

  final int seed;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final r = size.width / 2;
    final angle = rng.nextDouble() * math.pi * 2;
    final lx = math.cos(angle), ly = math.sin(angle);
    final pts = <double>[];
    for (var i = 0; i < 1400; i++) {
      final x = rng.nextDouble() * 2 - 1, y = rng.nextDouble() * 2 - 1;
      final dist = math.sqrt(x * x + y * y);
      if (dist > 1.06) continue;
      final rim = math.exp(-(1 - dist).abs() / 0.12);
      final side = (0.5 + 0.5 * (x * lx + y * ly)).clamp(0.0, 1.0);
      final p = dist > 1 ? 0.25 * rim : 0.05 + 0.55 * rim * (0.35 + 0.65 * side);
      if (rng.nextDouble() < p) {
        pts
          ..add(r + x * r)
          ..add(r + y * r);
      }
    }
    final paint = Paint()
      ..color = ink.withValues(alpha: 0.7)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.square;
    canvas.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts), paint);
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.seed != seed || old.ink != ink;
}

/// The small dark pill navigation from the reference designs.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelMedium;
    return Glass(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 30,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < values.length; i++)
                Semantics(
                  selected: values[i] == selected,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelected(values[i]),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: values[i] == selected ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        labels[i],
                        style: text?.copyWith(
                          color: values[i] == selected ? Graphite.chalk : Graphite.chalk.withValues(alpha: 0.55),
                          fontWeight: values[i] == selected ? FontWeight.w600 : FontWeight.w400,
                          letterSpacing: 0.2,
                        ),
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
