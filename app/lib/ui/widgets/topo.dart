import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'raster.dart';

/// Topographic contour lines over a smooth noise field, with an optional peak at [focus].
class TopoBackground extends StatelessWidget {
  const TopoBackground({
    super.key,
    this.focus = Alignment.center,
    this.peak = 0,
    this.seed = 1,
    this.levels = 22,
    this.fadeBottom = false,
    this.fadeTo,
    this.opacity = 1,
  });

  final Alignment focus;
  final double peak;
  final int seed;
  final int levels;
  final bool fadeBottom;
  final double? fadeTo;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final fade = fadeBottom || fadeTo != null ? (fadeTo ?? 0, fadeTo == null ? 0.35 : 0.55) : null;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _TopoPainter(
            _TopoSpec(focus, peak, seed, levels),
            ink.withValues(alpha: opacity),
            fade,
            MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
    );
  }
}

@immutable
class _TopoSpec {
  const _TopoSpec(this.focus, this.peak, this.seed, this.levels);

  final Alignment focus;
  final double peak;
  final int seed;
  final int levels;

  @override
  bool operator ==(Object other) =>
      other is _TopoSpec && other.focus == focus && other.peak == peak && other.seed == seed && other.levels == levels;

  @override
  int get hashCode => Object.hash(focus, peak, seed, levels);
}

class _Contours {
  _Contours(this.minor, this.major);

  final Float32List minor;
  final Float32List major;
}

final _cache = <(Size, _TopoSpec), _Contours>{};

double _hash(int x, int y, int seed) {
  final s = math.sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453;
  return s - s.floorToDouble();
}

double _noise(double x, double y, int seed) {
  final xi = x.floor(), yi = y.floor();
  final xf = x - xi, yf = y - yi;
  final u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  final a = _hash(xi, yi, seed), b = _hash(xi + 1, yi, seed);
  final c = _hash(xi, yi + 1, seed), d = _hash(xi + 1, yi + 1, seed);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

double _fbm(double x, double y, int seed) =>
    _noise(x, y, seed) + 0.5 * _noise(x * 2.03, y * 2.03, seed + 1) + 0.25 * _noise(x * 4.1, y * 4.1, seed + 2);

_Contours _build(Size size, _TopoSpec spec) {
  const cell = 5.0;
  final cols = (size.width / cell).ceil() + 1;
  final rows = (size.height / cell).ceil() + 1;
  final fx = (spec.focus.x + 1) / 2 * size.width;
  final fy = (spec.focus.y + 1) / 2 * size.height;
  final sigma = 0.3 * math.min(size.width, size.height);
  final field = Float64List(cols * rows);
  var lo = double.infinity, hi = -double.infinity;
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final x = i * cell, y = j * cell;
      final wx = x + 60 * _fbm(x / 260, y / 260, spec.seed + 9);
      final wy = y + 60 * _fbm(x / 260 + 5.2, y / 260 + 1.3, spec.seed + 9);
      final r2 = math.pow(wx - fx, 2) + math.pow(wy - fy, 2);
      final v = _fbm(wx / 210, wy / 210, spec.seed) + spec.peak * math.exp(-r2 / (2 * sigma * sigma));
      field[j * cols + i] = v;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
  }

  final minor = <double>[], major = <double>[];
  final step = (hi - lo) / (spec.levels + 1);
  for (var k = 1; k <= spec.levels; k++) {
    final level = lo + step * k;
    final out = k % 5 == 0 ? major : minor;
    for (var j = 0; j < rows - 1; j++) {
      for (var i = 0; i < cols - 1; i++) {
        final tl = field[j * cols + i], tr = field[j * cols + i + 1];
        final bl = field[(j + 1) * cols + i], br = field[(j + 1) * cols + i + 1];
        final idx = (tl > level ? 8 : 0) | (tr > level ? 4 : 0) | (br > level ? 2 : 0) | (bl > level ? 1 : 0);
        if (idx == 0 || idx == 15) continue;
        final x0 = i * cell, y0 = j * cell;
        (double, double) edge(int e) => switch (e) {
          0 => (x0 + cell * (level - tl) / (tr - tl), y0),
          1 => (x0 + cell, y0 + cell * (level - tr) / (br - tr)),
          2 => (x0 + cell * (level - bl) / (br - bl), y0 + cell),
          _ => (x0, y0 + cell * (level - tl) / (bl - tl)),
        };
        void seg(int a, int b) {
          final p = edge(a), q = edge(b);
          out
            ..add(p.$1)
            ..add(p.$2)
            ..add(q.$1)
            ..add(q.$2);
        }

        switch (idx) {
          case 1 || 14:
            seg(3, 2);
          case 2 || 13:
            seg(2, 1);
          case 3 || 12:
            seg(3, 1);
          case 4 || 11:
            seg(0, 1);
          case 6 || 9:
            seg(0, 2);
          case 7 || 8:
            seg(3, 0);
          case 5:
            seg(3, 0);
            seg(2, 1);
          case 10:
            seg(0, 1);
            seg(3, 2);
        }
      }
    }
  }
  return _Contours(Float32List.fromList(minor), Float32List.fromList(major));
}

class _TopoPainter extends CustomPainter {
  _TopoPainter(this.spec, this.ink, this.fade, this.dpr);

  final _TopoSpec spec;
  final Color ink;
  final (double, double)? fade;
  final double dpr;

  static final _images = RasterCache(6);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final image = _images.get((size, spec, ink, fade, dpr), size, dpr, (c) => _draw(c, size));
    drawRaster(canvas, image, Offset.zero & size);
  }

  void _draw(Canvas canvas, Size size) {
    final key = (size, spec);
    final contours = _cache[key] ??= _build(size, spec);
    if (_cache.length > 6) _cache.remove(_cache.keys.first);
    final fade = this.fade;
    if (fade != null) canvas.saveLayer(Offset.zero & size, Paint());
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawRawPoints(
      ui.PointMode.lines,
      contours.minor,
      paint
        ..color = ink.withValues(alpha: ink.a * 0.13)
        ..strokeWidth = 0.7,
    );
    canvas.drawRawPoints(
      ui.PointMode.lines,
      contours.major,
      paint
        ..color = ink.withValues(alpha: ink.a * 0.28)
        ..strokeWidth = 1.1,
    );
    if (fade != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.white.withValues(alpha: fade.$1)],
            stops: [0, fade.$2, 1],
          ).createShader(Offset.zero & size),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TopoPainter old) =>
      old.spec != spec || old.ink != ink || old.fade != fade || old.dpr != dpr;
}

/// Gives every pushed page the graphite base and a contour field, then runs the usual zoom transition.
class ContourPageTransitions extends PageTransitionsBuilder {
  const ContourPageTransitions();

  static const _inner = ZoomPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _inner.buildTransitions(route, context, animation, secondaryAnimation, ContourPage(child: child));
}

class ContourPage extends StatelessWidget {
  const ContourPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Stack(children: [
          const Positioned.fill(
            child: TopoBackground(seed: 8, focus: Alignment(0.7, -0.65), peak: 0.9, levels: 24, fadeTo: 0.3),
          ),
          Positioned.fill(child: BackdropGroup(child: child)),
        ]),
      );
}
