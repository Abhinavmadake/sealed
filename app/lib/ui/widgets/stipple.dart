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

/// A padlock drawn as a stippled point cloud. The dots start on a huge scattered ring, much of it
/// off-screen, fade in and drift inward along gentle arcs until they form the lock. With [dust], a
/// sparse field of loose dots spreads over the whole screen and thins out towards its edges.
class StippleLock extends StatefulWidget {
  const StippleLock({super.key, this.seed = 11, this.dust = true});

  final int seed;
  final bool dust;

  @override
  State<StippleLock> createState() => _StippleLockState();
}

class _StippleLockState extends State<StippleLock> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
  List<_Cloud>? _clouds;
  Object? _job;

  /// Lays out the dots on a background isolate, then starts the animation once they are ready.
  void _prepare(Size size, double reach) {
    if (!mounted) return;
    Rect? screen;
    if (widget.dust) {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero);
      final s = MediaQuery.sizeOf(context);
      screen = Rect.fromLTWH(-origin.dx, -origin.dy, s.width, s.height);
    }
    final job = (size.width, size.height, reach, widget.seed, screen);
    if (job == _job) return;
    _job = job;
    compute(_makeClouds, job).then((clouds) {
      if (!mounted || _job != job) return;
      setState(() => _clouds = clouds);
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screen = MediaQuery.sizeOf(context);
    final reach = math.sqrt(screen.width * screen.width + screen.height * screen.height) / 2;
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      WidgetsBinding.instance.addPostFrameCallback((_) => _prepare(size, reach));
      final clouds = _clouds;
      if (clouds == null) return SizedBox.fromSize(size: size);
      return RepaintBoundary(
        child: CustomPaint(size: size, painter: _CloudPainter(clouds, _controller, ink, dpr)),
      );
    });
  }
}

List<_Cloud> _makeClouds((double, double, double, int, Rect?) job) {
  final (w, h, reach, seed, screen) = job;
  final size = Size(w, h);
  return [
    _Cloud.lock(size, reach, seed),
    if (screen != null) _Cloud.dust(size, reach, seed + 1, screen),
  ];
}

/// Points sorted by dot size, each with its resting place, its start offset and a sideways bend.
class _Cloud {
  _Cloud._(this.size, this.reach, this.screen, this.target, this.start, this.bend, this.delay, this.bucketEnd);

  final Size size;
  final double reach;
  final Rect? screen;
  final Float32List target;
  final Float32List start;
  final Float32List bend;
  final Float32List delay;
  final List<int> bucketEnd;

  static const sizes = [1.05, 1.6, 2.4];
  static const alphas = [0.95, 0.7, 0.3];
  static const maxPoints = 34000;

  int get length => delay.length;

  static _Cloud _build(Size size, double reach, Rect? screen, math.Random rng, List<double> xs, List<double> ys) {
    final cx = size.width / 2, cy = size.height / 2;
    final n = xs.length;
    final buckets = List<int>.generate(n, (_) {
      final r = rng.nextDouble();
      return r < 0.72 ? 0 : (r < 0.95 ? 1 : 2);
    });
    final order = List<int>.generate(n, (i) => i)..sort((a, b) => buckets[a] - buckets[b]);
    final target = Float32List(n * 2), start = Float32List(n * 2), bend = Float32List(n * 2);
    final delay = Float32List(n);
    final bucketEnd = [0, 0, 0];
    final swirl = rng.nextBool() ? 1.0 : -1.0;
    for (var k = 0; k < n; k++) {
      final i = order[k];
      final x = xs[i], y = ys[i];
      final angle = rng.nextDouble() * math.pi * 2;
      final radius = reach * (0.55 + 0.75 * math.sqrt(rng.nextDouble()));
      final sx = cx + math.cos(angle) * radius - x;
      final sy = cy + math.sin(angle) * radius - y;
      final curl = swirl * (0.25 + 0.35 * rng.nextDouble());
      target[k * 2] = x;
      target[k * 2 + 1] = y;
      start[k * 2] = sx;
      start[k * 2 + 1] = sy;
      bend[k * 2] = -sy * curl;
      bend[k * 2 + 1] = sx * curl;
      delay[k] = rng.nextDouble() * 0.32;
      bucketEnd[buckets[i]] = k + 1;
    }
    for (var b = 1; b < 3; b++) {
      if (bucketEnd[b] < bucketEnd[b - 1]) bucketEnd[b] = bucketEnd[b - 1];
    }
    return _Cloud._(size, reach, screen, target, start, bend, delay, bucketEnd);
  }

  factory _Cloud.lock(Size size, double reach, int seed) {
    final rng = math.Random(seed);
    final side = math.min(size.width, size.height / 1.1);
    final ox = (size.width - side) / 2;
    final oy = (size.height - side * 1.1) / 2;
    final area = size.width * size.height;
    final candidates = math.min(area * 1.7, maxPoints / 0.22).round();
    final xs = <double>[], ys = <double>[];
    for (var i = 0; i < candidates; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      if (rng.nextDouble() < _lockDensity((x - ox) / side, (y - oy) / side)) {
        xs.add(x);
        ys.add(y);
      }
    }
    return _build(size, reach, null, rng, xs, ys);
  }

  factory _Cloud.dust(Size size, double reach, int seed, Rect screen) {
    final rng = math.Random(seed);
    final cx = size.width / 2, cy = size.height / 2;
    final fade = 0.16 * math.min(screen.width, screen.height);
    final extent = math.max(
      math.max((screen.left - cx).abs(), (screen.right - cx).abs()),
      math.max((screen.top - cy).abs(), (screen.bottom - cy).abs()),
    );
    final candidates = math.min((screen.width * screen.height * 0.1).round(), 140000);
    final xs = <double>[], ys = <double>[];
    for (var i = 0; i < candidates; i++) {
      final x = screen.left + rng.nextDouble() * screen.width;
      final y = screen.top + rng.nextDouble() * screen.height;
      final dx = x - cx, dy = y - cy;
      final r = math.sqrt(dx * dx + dy * dy) / extent;
      if (r >= 1) continue;
      final f = 1 - r;
      final falloff = f * f * math.sqrt(f);
      final edge = math.min(math.min(x - screen.left, screen.right - x), math.min(y - screen.top, screen.bottom - y));
      final soft = (edge / fade).clamp(0.0, 1.0);
      final clump = 0.55 + 0.45 * math.sin(x * 0.031 + y * 0.017) * math.sin(y * 0.027 - x * 0.013 + 1.3);
      if (rng.nextDouble() < 0.32 * falloff * soft * soft * clump) {
        xs.add(x);
        ys.add(y);
      }
    }
    return _build(size, reach, screen, rng, xs, ys);
  }
}

double _sdRoundRect(double px, double py, double cx, double cy, double hw, double hh, double r) {
  final qx = (px - cx).abs() - hw + r;
  final qy = (py - cy).abs() - hh + r;
  final outside = math.sqrt(math.max(qx, 0) * math.max(qx, 0) + math.max(qy, 0) * math.max(qy, 0));
  return outside + math.min(math.max(qx, qy), 0) - r;
}

/// Probability of a dot at (u, v) in a 1 x 1.1 box.
double _lockDensity(double u, double v) {
  final body = _sdRoundRect(u, v, 0.5, 0.76, 0.31, 0.23, 0.05);
  final double arc;
  if (v <= 0.48) {
    arc = (math.sqrt((u - 0.5) * (u - 0.5) + (v - 0.48) * (v - 0.48)) - 0.19).abs() - 0.045;
  } else {
    arc = math.max(math.min((u - 0.31).abs(), (u - 0.69).abs()) - 0.045, v - 0.56);
  }
  final hole = math.min(
    math.sqrt((u - 0.5) * (u - 0.5) + (v - 0.71) * (v - 0.71)) - 0.045,
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
  return 0.5 * math.exp(-d / 0.009);
}

class _CloudPainter extends CustomPainter {
  _CloudPainter(this.clouds, this.progress, this.ink, this.dpr) : super(repaint: progress);

  final List<_Cloud> clouds;
  final Animation<double> progress;
  final Color ink;
  final double dpr;

  static final _settled = RasterCache(3);

  static const _steps = 8;
  static const _span = 0.68;
  static final _buffers = <Float32List>[];
  static final _fill = List.filled(_steps, 0);

  static Float32List _buffer(int step, int needed) {
    while (_buffers.length < _steps) {
      _buffers.add(Float32List(0));
    }
    if (_buffers[step].length < needed) _buffers[step] = Float32List(needed + needed ~/ 4);
    return _buffers[step];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t < 1) {
      _points(canvas, t);
      return;
    }
    var bounds = Offset.zero & size;
    for (final c in clouds) {
      if (c.screen != null) bounds = bounds.expandToInclude(c.screen!);
    }
    final image = _settled.get((clouds.first, clouds.last, ink, dpr), bounds.size, dpr, (c) {
      c.translate(-bounds.left, -bounds.top);
      _points(c, 1);
    });
    drawRaster(canvas, image, bounds);
  }

  void _points(Canvas canvas, double t) {
    final paint = Paint();
    for (final cloud in clouds) {
      var from = 0;
      for (var b = 0; b < 3; b++) {
        final to = cloud.bucketEnd[b];
        if (to > from) _paintBucket(canvas, paint, cloud, b, from, to, t);
        from = to;
      }
    }
  }

  void _paintBucket(Canvas canvas, Paint paint, _Cloud c, int bucket, int from, int to, double t) {
    final capacity = (to - from) * 2;
    final buffers = [for (var s = 0; s < _steps; s++) _buffer(s, capacity)];
    _fill.fillRange(0, _steps, 0);
    final target = c.target, start = c.start, bend = c.bend, delay = c.delay;
    for (var i = from; i < to; i++) {
      final local = (t - delay[i]) / _span;
      if (local <= 0) continue;
      double x = target[i * 2], y = target[i * 2 + 1];
      var step = _steps - 1;
      if (local < 1) {
        final q = 2 - 2 * local;
        final e = local < 0.5 ? 4 * local * local * local : 1 - q * q * q / 2;
        final away = 1 - e;
        final arc = away * e * 2;
        x += start[i * 2] * away + bend[i * 2] * arc;
        y += start[i * 2 + 1] * away + bend[i * 2 + 1] * arc;
        final f = (local * 2.4).clamp(0.0, 1.0);
        step = (f * f * (3 - 2 * f) * (_steps - 1)).round();
        if (step == 0) continue;
      }
      final buf = buffers[step];
      final j = _fill[step];
      buf[j] = x;
      buf[j + 1] = y;
      _fill[step] = j + 2;
    }
    paint
      ..strokeWidth = _Cloud.sizes[bucket]
      ..strokeCap = bucket == 2 ? StrokeCap.round : StrokeCap.square;
    for (var s = 1; s < _steps; s++) {
      if (_fill[s] == 0) continue;
      paint.color = ink.withValues(alpha: _Cloud.alphas[bucket] * s / (_steps - 1));
      canvas.drawRawPoints(ui.PointMode.points, Float32List.sublistView(buffers[s], 0, _fill[s]), paint);
    }
  }

  @override
  bool shouldRepaint(_CloudPainter old) =>
      old.ink != ink || old.dpr != dpr || old.clouds.length != clouds.length || !identical(old.clouds.first, clouds.first) ||
      (clouds.length > 1 && !identical(old.clouds.last, clouds.last));
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
