import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass.dart';

const _radius = 22.0;

const panelFill = Color(0x52000000);

const panelEdge = BorderSide(color: Color(0x1FFFFFFF), width: 0.8);

const _blur = 16.0;
const _tint = 0.055;

/// A frosted glass card that lifts content off the contour background.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Glass(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(_radius))),
        blur: _blur,
        tint: _tint,
        fill: panelFill,
        grouped: true,
        child: Material(type: MaterialType.transparency, child: Padding(padding: padding, child: child)),
      );
}

/// Rows grouped on one panel with hairlines between them, like an inset grouped list.
class PanelGroup extends StatelessWidget {
  const PanelGroup({super.key, required this.children, this.dividerIndent = 20});

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) => Panel(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: dividerIndent),
            children[i],
          ],
        ]),
      );
}

/// One row of a grouped list built lazily, rounded only at the ends of the group.
class GroupCell extends StatelessWidget {
  const GroupCell({super.key, required this.first, required this.last, required this.child, this.dividerIndent = 20});

  final bool first;
  final bool last;
  final Widget child;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(_radius);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: first ? r : Radius.zero, bottom: last ? r : Radius.zero),
    );
    return Glass(
      shape: shape,
      blur: _blur,
      tint: _tint,
      fill: panelFill,
      grouped: true,
      flat: true,
      rim: false,
      child: CustomPaint(
        foregroundPainter: _CellRim(shape, first, last),
        child: Material(
          type: MaterialType.transparency,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            child,
            if (!last) Divider(height: 1, indent: dividerIndent),
          ]),
        ),
      ),
    );
  }
}

/// The outline of a grouped list, drawn piecewise so the edges between rows stay open.
class _CellRim extends CustomPainter {
  _CellRim(this.shape, this.first, this.last);

  final ShapeBorder shape;
  final bool first;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-2, first ? -2 : 1, size.width + 2, last ? size.height + 2 : size.height - 1));
    canvas.drawPath(
      shape.getOuterPath((Offset.zero & size).deflate(0.4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0x24FFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CellRim old) => old.first != first || old.last != last || old.shape != shape;
}

/// A small uppercase label above a panel.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
      child: Text(text.toUpperCase(), style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
    );
  }
}

/// Side margins for scrolling content: at least 20, and a centred column of at most 760 on wide screens.
EdgeInsets listInsets(BuildContext context, {double top = 0, double bottom = 32}) {
  final side = math.max(20.0, (MediaQuery.sizeOf(context).width - 760) / 2);
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}
