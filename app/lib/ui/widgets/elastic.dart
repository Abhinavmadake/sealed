import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Stretches its child vertically while dragged, with rubber-band resistance, and springs back on
/// release. Pulling down stretches away from the top edge, pulling up away from the bottom.
class ElasticStretch extends StatefulWidget {
  const ElasticStretch({super.key, required this.child, this.maxStretch = 0.09});

  final Widget child;
  final double maxStretch;

  @override
  State<ElasticStretch> createState() => _ElasticStretchState();
}

class _ElasticStretchState extends State<ElasticStretch> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController.unbounded(vsync: this);
  double _pull = 0;

  static const _spring = SpringDescription(mass: 1, stiffness: 260, damping: 22);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d, double height) {
    _controller.stop();
    _pull += d.delta.dy;
    final limit = height * widget.maxStretch;
    final rubber = limit * (1 - 1 / (1 + _pull.abs() / limit / 1.6));
    _controller.value = _pull.sign * rubber / height;
  }

  void _end(DragEndDetails d, double height) {
    _pull = 0;
    final velocity = (d.primaryVelocity ?? 0) / height * 0.1;
    _controller.animateWith(SpringSimulation(_spring, _controller.value, 0, velocity));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final height = box.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (d) => _update(d, height),
          onVerticalDragEnd: (d) => _end(d, height),
          onVerticalDragCancel: () => _end(DragEndDetails(primaryVelocity: 0), height),
          child: AnimatedBuilder(
            animation: _controller,
            child: widget.child,
            builder: (context, child) {
              final k = _controller.value;
              if (k == 0) return child!;
              return Transform(
                alignment: k > 0 ? Alignment.topCenter : Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(1, 1 + k.abs(), 1),
                child: child,
              );
            },
          ),
        );
      });
}
