import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass.dart';

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
          painter: _GrainPainter(scheme.onSurface.withValues(alpha: dark ? 0.07 : 0.09), density),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.color, this.density);

  final Color color;
  final double density;

  @override
  void paint(Canvas canvas, Size size) {
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
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.9;
    canvas.drawRawPoints(ui.PointMode.points, fine, paint);
    canvas.drawRawPoints(ui.PointMode.points, coarse, paint..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.color != color || old.density != density;
}

/// A padlock drawn as a stippled point cloud that drifts in from the right and settles.
class StippleLock extends StatefulWidget {
  const StippleLock({super.key, this.seed = 11, this.dust = true});

  final int seed;
  final bool dust;

  @override
  State<StippleLock> createState() => _StippleLockState();
}

class _StippleLockState extends State<StippleLock> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  _Cloud? _cloud;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        if (_cloud?.size != size) _cloud = _Cloud.lock(size, widget.seed, widget.dust);
        return RepaintBoundary(
          child: CustomPaint(size: size, painter: _CloudPainter(_cloud!, _controller, ink)),
        );
      },
    );
  }
}

class _Cloud {
  _Cloud(this.size, this.target, this.offset, this.delay, this.bucket);

  final Size size;
  final Float32List target;
  final Float32List offset;
  final Float32List delay;
  final Uint8List bucket;

  static const sizes = [0.75, 1.3, 2.3];
  static const alphas = [0.9, 0.6, 0.25];

  int get length => delay.length;

  factory _Cloud.lock(Size size, int seed, bool dust) {
    final rng = math.Random(seed);
    final side = math.min(size.width, size.height / 1.1);
    final ox = (size.width - side) / 2;
    final oy = (size.height - side * 1.1) / 2;
    final candidates = (size.width * size.height * 1.7).round();
    final tx = <double>[], ty = <double>[], ex = <double>[], ey = <double>[], dl = <double>[];
    final bk = <int>[];
    for (var i = 0; i < candidates; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final d = _lockDensity((x - ox) / side, (y - oy) / side, dust);
      if (rng.nextDouble() >= d) continue;
      tx.add(x);
      ty.add(y);
      ex.add((0.15 + rng.nextDouble() * 0.85) * size.width * 0.7);
      ey.add((rng.nextDouble() - 0.6) * size.height * 0.35);
      dl.add(rng.nextDouble() * 0.4);
      final r = rng.nextDouble();
      bk.add(r < 0.72 ? 0 : (r < 0.95 ? 1 : 2));
    }
    final target = Float32List(tx.length * 2);
    final offset = Float32List(tx.length * 2);
    for (var i = 0; i < tx.length; i++) {
      target[i * 2] = tx[i];
      target[i * 2 + 1] = ty[i];
      offset[i * 2] = ex[i];
      offset[i * 2 + 1] = ey[i];
    }
    return _Cloud(size, target, offset, Float32List.fromList(dl), Uint8List.fromList(bk));
  }
}

double _sdRoundRect(double px, double py, double cx, double cy, double hw, double hh, double r) {
  final qx = (px - cx).abs() - hw + r;
  final qy = (py - cy).abs() - hh + r;
  final outside = math.sqrt(math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2));
  return outside + math.min(math.max(qx, qy), 0) - r;
}

/// Probability of a dot at (u, v) in a 1 x 1.1 box.
double _lockDensity(double u, double v, bool dust) {
  final body = _sdRoundRect(u, v, 0.5, 0.76, 0.31, 0.23, 0.05);
  final double arc;
  if (v <= 0.48) {
    arc = (math.sqrt(math.pow(u - 0.5, 2) + math.pow(v - 0.48, 2)) - 0.19).abs() - 0.045;
  } else {
    arc = math.max(math.min((u - 0.31).abs(), (u - 0.69).abs()) - 0.045, v - 0.56);
  }
  final hole = math.min(
    math.sqrt(math.pow(u - 0.5, 2) + math.pow(v - 0.71, 2)) - 0.045,
    _sdRoundRect(u, v, 0.5, 0.79, 0.016, 0.06, 0.01),
  );
  final d = math.max(math.min(body, arc), -hole);
  final grain = 0.5 + 0.5 * math.sin(17.3 * u + 9.1 * v) * math.sin(11.7 * v - 6.3 * u + 1.9);

  if (d < 0) {
    final shade = ((0.62 - u) * 0.9 + (v - 0.5) * 1.1).clamp(0.0, 1.0);
    final rim = 0.35 * math.exp(d / 0.016);
    final keyhole = 0.4 * math.exp(-hole.abs() / 0.012);
    return ((0.08 + 0.55 * shade + rim + keyhole) * (0.7 + 0.45 * grain)).clamp(0.0, 0.9);
  }
  final halo = 0.5 * math.exp(-d / 0.009);
  if (!dust) return halo;
  final drift = (0.35 + 0.65 * ((u - 0.45) * 2).clamp(0.0, 1.0)) * (0.6 + 0.6 * grain);
  return halo + 0.07 * math.exp(-d / 0.11) * drift;
}

class _CloudPainter extends CustomPainter {
  _CloudPainter(this.cloud, this.progress, this.ink) : super(repaint: progress);

  final _Cloud cloud;
  final Animation<double> progress;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final counts = List.filled(3, 0);
    for (var i = 0; i < cloud.length; i++) {
      counts[cloud.bucket[i]]++;
    }
    final points = [for (final c in counts) Float32List(c * 2)];
    final fill = List.filled(3, 0);
    for (var i = 0; i < cloud.length; i++) {
      final local = ((t - cloud.delay[i]) / 0.6).clamp(0.0, 1.0);
      final away = math.pow(1 - local, 3).toDouble();
      final b = cloud.bucket[i];
      final j = fill[b];
      points[b][j] = cloud.target[i * 2] + cloud.offset[i * 2] * away;
      points[b][j + 1] = cloud.target[i * 2 + 1] + cloud.offset[i * 2 + 1] * away;
      fill[b] = j + 2;
    }
    final fade = Curves.easeOut.transform(t.clamp(0.0, 1.0));
    for (var b = 0; b < 3; b++) {
      final paint = Paint()
        ..color = ink.withValues(alpha: _Cloud.alphas[b] * (0.35 + 0.65 * fade))
        ..strokeWidth = _Cloud.sizes[b]
        ..strokeCap = StrokeCap.round;
      canvas.drawRawPoints(ui.PointMode.points, points[b], paint);
    }
  }

  @override
  bool shouldRepaint(_CloudPainter old) => old.cloud != cloud || old.ink != ink;
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
      ..strokeCap = StrokeCap.round;
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
