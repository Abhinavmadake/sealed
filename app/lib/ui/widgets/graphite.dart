import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'raster.dart';

final Future<ui.FragmentProgram> _program = ui.FragmentProgram.fromAsset('shaders/graphite.frag');

void _uniforms(
  ui.FragmentShader s, {
  required Size area,
  required double dpr,
  required double progress,
  required Color ink,
  required Color base,
  Rect? lock,
  (Offset, Offset, double, double)? beam,
}) {
  var i = 0;
  void f(double v) => s.setFloat(i++, v);
  f(area.width);
  f(area.height);
  f(dpr);
  f(progress);
  f(lock?.left ?? 0);
  f(lock?.top ?? 0);
  f(lock?.width ?? 0);
  f(lock == null ? 0 : 1);
  final (from, to, width, strength) = beam ?? (Offset.zero, const Offset(1, 1), 1.0, 0.0);
  f(from.dx);
  f(from.dy);
  f(to.dx);
  f(to.dy);
  f(width);
  f(strength);
  f(ink.r);
  f(ink.g);
  f(ink.b);
  f(base.r);
  f(base.g);
  f(base.b);
}

mixin _ShaderLoader<T extends StatefulWidget> on State<T> {
  ui.FragmentShader? shader;

  void onShaderReady() {}

  @override
  void initState() {
    super.initState();
    _program.then((p) {
      if (!mounted) return;
      setState(() => shader = p.fragmentShader());
      onShaderReady();
    });
  }

  @override
  void dispose() {
    shader?.dispose();
    super.dispose();
  }
}

/// A padlock made of light: fine grain gathers into a lit form that dissolves into the dark
/// towards its base. It lights up grain by grain from the upper right when it first appears.
class GrainLock extends StatefulWidget {
  const GrainLock({super.key});

  @override
  State<GrainLock> createState() => _GrainLockState();
}

class _GrainLockState extends State<GrainLock> with SingleTickerProviderStateMixin, _ShaderLoader {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void onShaderReady() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
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
    final s = shader;
    if (s == null) return const SizedBox.expand();
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _LockPainter(s, _controller, scheme.onSurface, scheme.surface, MediaQuery.devicePixelRatioOf(context)),
        ),
      ),
    );
  }
}

class _LockPainter extends CustomPainter {
  _LockPainter(this.shader, this.progress, this.ink, this.base, this.dpr) : super(repaint: progress);

  final ui.FragmentShader shader;
  final Animation<double> progress;
  final Color ink;
  final Color base;
  final double dpr;

  static final _settled = RasterCache(2);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = math.min(size.width, size.height / 1.1);
    final lock = Rect.fromLTWH((size.width - side) / 2, (size.height - side * 1.1) / 2, side, side * 1.1);
    final bounds = lock.inflate(side * 0.6);
    void draw(Canvas c, double t) {
      _uniforms(shader, area: bounds.size, dpr: dpr, progress: t, ink: ink, base: base, lock: lock);
      c.drawRect(bounds, Paint()..shader = shader);
    }

    if (progress.value < 1) {
      draw(canvas, progress.value);
      return;
    }
    final image = _settled.get((size, ink, base, dpr), bounds.size, dpr, (c) {
      c.translate(-bounds.left, -bounds.top);
      draw(c, 1);
    });
    drawRaster(canvas, image, bounds);
  }

  @override
  bool shouldRepaint(_LockPainter old) => old.ink != ink || old.base != base || old.dpr != dpr || old.shader != shader;
}

/// A hazy shaft of light from the upper right, aimed just past [toward].
class LightBeam extends StatefulWidget {
  const LightBeam({super.key, this.toward = const Alignment(0, -0.15), this.strength = 0.45});

  final Alignment toward;
  final double strength;

  @override
  State<LightBeam> createState() => _LightBeamState();
}

class _LightBeamState extends State<LightBeam> with _ShaderLoader {
  @override
  Widget build(BuildContext context) {
    final s = shader;
    if (s == null) return const SizedBox.expand();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BeamPainter(
          s,
          widget.toward,
          widget.strength,
          Theme.of(context).colorScheme.onSurface,
          MediaQuery.devicePixelRatioOf(context),
        ),
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  _BeamPainter(this.shader, this.toward, this.strength, this.ink, this.dpr);

  final ui.FragmentShader shader;
  final Alignment toward;
  final double strength;
  final Color ink;
  final double dpr;

  static final _images = RasterCache(2);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final image = _images.get((size, toward, strength, ink, dpr), size, dpr, (c) {
      final target = toward.alongSize(size);
      final w = math.min(size.width, size.height * 0.6);
      final from = Offset(size.width + w * 0.09, target.dy - w * 0.68);
      final to = target + Offset(-w * 0.15, w * 0.2);
      _uniforms(shader,
          area: size, dpr: dpr, progress: 1, ink: ink, base: Colors.black, beam: (from, to, w * 0.3, strength));
      c.drawRect(Offset.zero & size, Paint()..shader = shader);
    });
    drawRaster(canvas, image, Offset.zero & size);
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.toward != toward || old.strength != strength || old.ink != ink || old.dpr != dpr || old.shader != shader;
}
