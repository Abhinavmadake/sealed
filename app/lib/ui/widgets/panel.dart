import 'package:flutter/material.dart';

const _radius = 22.0;

Color panelFill(BuildContext context) => Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.94);

const panelEdge = BorderSide(color: Color(0x1FFFFFFF), width: 0.8);

/// A solid card that lifts content off the contour background.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
        color: panelFill(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(_radius)), side: panelEdge),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
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
    return Material(
      color: panelFill(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: first ? r : Radius.zero, bottom: last ? r : Radius.zero),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        child,
        if (!last) Divider(height: 1, indent: dividerIndent),
      ]),
    );
  }
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
