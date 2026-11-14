import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sync/vault_repository.dart';
import '../../models/vault_item.dart';
import '../../services/vault_service.dart';
import '../generator/generator_screen.dart';
import '../health/health_screen.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/panel.dart';
import '../widgets/stipple.dart';
import '../widgets/topo.dart';
import 'item_detail_screen.dart';
import 'item_edit_screen.dart';

enum _Filter { all, favorites, logins, notes, shared }

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _search = TextEditingController();
  final _pages = PageController();
  final _capsule = GlobalKey();
  bool _searching = false;
  _Filter _filter = _Filter.all;

  static const _labels = ['All', 'Favourites', 'Logins', 'Notes', 'Shared'];

  @override
  void dispose() {
    _search.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _showFilter(_Filter f) {
    setState(() => _filter = f);
    _pages.animateToPage(f.index, duration: const Duration(milliseconds: 340), curve: Curves.easeOutCubic);
  }

  void _setSearching(bool on) {
    setState(() {
      _searching = on;
      if (!on) _search.clear();
    });
    if (!on) FocusScope.of(context).unfocus();
  }

  Future<void> _openMenu(VaultService service) async {
    final navBox = Navigator.of(context).context.findRenderObject() as RenderBox;
    final box = _capsule.currentContext!.findRenderObject() as RenderBox;
    final anchor = box.localToGlobal(Offset.zero, ancestor: navBox) & box.size;
    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 360),
      pageBuilder: (context, animation, _) => _MorphMenu(anchor: anchor, animation: animation),
      transitionBuilder: (context, animation, _, child) => child,
    );
    if (!mounted) return;
    switch (choice) {
      case 'generator':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const GeneratorScreen()));
      case 'health':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const HealthScreen()));
      case 'settings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      case 'lock':
        service.lock();
    }
  }

  bool _matches(VaultEntry e, _Filter filter) {
    final item = e.item;
    final ok = switch (filter) {
      _Filter.all => true,
      _Filter.favorites => item.favorite,
      _Filter.logins => item.type == ItemType.login,
      _Filter.notes => item.type == ItemType.note,
      _Filter.shared => e.sharedWithMe,
    };
    if (!ok) return false;
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [item.title, item.username, item.url].any((f) => f.toLowerCase().contains(q));
  }

  void _new() async {
    final type = await showDialog<ItemType>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => const _NewItemDialog(),
    );
    if (type != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ItemEditScreen(newType: type)));
    }
  }

  Future<void> _reauthenticate(VaultService service) async {
    final controller = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Sign in again'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This device was signed out by the server. Enter your current master password to keep syncing.',
              ),
              gap,
              ErrorText(error),
              PasswordField(controller: controller, label: 'Master password', autofocus: true),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
            FilledButton(
              onPressed: () async {
                try {
                  await service.reauthenticate(controller.text);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  setState(() => error = friendlyError(e));
                }
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _syncButton(VaultService s) {
    final scheme = Theme.of(context).colorScheme;
    if (s.syncing) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final (icon, tip, color) = s.sessionExpired
        ? (Icons.sync_problem, 'Signed out by the server', scheme.error)
        : s.offline
        ? (Icons.cloud_off_outlined, 'Offline. Changes will sync later.', scheme.error)
        : s.pendingCount > 0
        ? (Icons.cloud_upload_outlined, '${s.pendingCount} change(s) waiting to sync', null)
        : (Icons.cloud_done_outlined, 'Synced', null);
    return IconButton(
      tooltip: tip,
      icon: Badge(
        isLabelVisible: s.pendingCount > 0,
        label: Text('${s.pendingCount}'),
        child: Icon(icon, color: color),
      ),
      onPressed: s.sessionExpired ? () => _reauthenticate(s) : s.sync,
    );
  }

  Widget _header(VaultService service) {
    final scheme = Theme.of(context).colorScheme;
    final title = Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Vault', style: Theme.of(context).textTheme.headlineSmall),
        TextSpan(text: '  sealed', style: serifAccent(context, size: 16).copyWith(color: scheme.onSurfaceVariant)),
      ]),
    );
    final icons = Row(
      key: const ValueKey('icons'),
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () => _setSearching(true)),
        _syncButton(service),
        IconButton(tooltip: 'Menu', icon: const Icon(Icons.more_vert), onPressed: () => _openMenu(service)),
      ],
    );
    final search = Row(
      key: const ValueKey('search'),
      children: [
        const SizedBox(width: 18),
        Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _search,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search your vault',
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        IconButton(tooltip: 'Close search', icon: const Icon(Icons.close), onPressed: () => _setSearching(false)),
      ],
    );
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 76,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              alignment: Alignment.centerLeft,
              children: [
                AnimatedOpacity(
                  opacity: _searching ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: title,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedContainer(
                    key: _capsule,
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                    width: _searching ? box.maxWidth : 156,
                    height: 54,
                    child: Glass(
                      child: SizedBox.expand(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: const Interval(0.35, 1, curve: Curves.easeOut),
                          switchOutCurve: const Interval(0.65, 1),
                          child: _searching ? search : icons,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(VaultService service, _Filter filter) {
    final scheme = Theme.of(context).colorScheme;
    final visible = service.entries.where((e) => _matches(e, filter)).toList();
    return RefreshIndicator(
      onRefresh: service.sync,
      child: visible.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 110),
                Icon(Icons.lock_outline, size: 52, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                const SizedBox(height: 20),
                Text(
                  service.entries.isEmpty ? 'Your vault is empty.\nTap New to add a login.' : 'Nothing matches.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            )
          : ListView.builder(
              padding: listInsets(context, top: 4, bottom: 110),
              itemCount: visible.length,
              itemBuilder: (context, i) => GroupCell(
                first: i == 0,
                last: i == visible.length - 1,
                dividerIndent: 76,
                child: _EntryTile(visible[i]),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VaultService>();
    final scheme = Theme.of(context).colorScheme;
    final count = service.entries.where((e) => _matches(e, _filter)).length;
    final conflicts = service.entries.where((e) => e.inConflict).length;

    return Backdrop(
      behind: const [
        Positioned.fill(
          child: TopoBackground(seed: 4, focus: Alignment(0.75, -0.6), peak: 0.9, levels: 24, fadeTo: 0.3),
        ),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(preferredSize: const Size.fromHeight(76), child: _header(service)),
        floatingActionButton: GlassButton(
          onPressed: _new,
          height: 60,
          fontSize: 16.5,
          icon: const Icon(Icons.add),
          child: const Text('New'),
        ),
        body: Column(
          children: [
            if (service.sessionExpired)
              MaterialBanner(
                content: const Text('This device was signed out, so changes are not syncing.'),
                leading: const Icon(Icons.sync_problem),
                actions: [TextButton(onPressed: () => _reauthenticate(service), child: const Text('Sign in'))],
              ),
            if (service.notices.isNotEmpty)
              MaterialBanner(
                content: Text(service.notices.join('\n')),
                leading: const Icon(Icons.info_outline),
                actions: [TextButton(onPressed: service.dismissNotices, child: const Text('Dismiss'))],
              ),
            if (conflicts > 0)
              MaterialBanner(
                backgroundColor: scheme.errorContainer,
                content: Text(
                  '$conflicts item(s) were changed on two devices and need your choice.',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
                leading: Icon(Icons.call_split, color: scheme.onErrorContainer),
                actions: [
                  TextButton(
                    onPressed: () {
                      final first = service.entries.firstWhere((e) => e.inConflict);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(id: first.item.id)));
                    },
                    child: const Text('Review'),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PillTabs<_Filter>(
                  values: _Filter.values,
                  labels: _labels,
                  selected: _filter,
                  onSelected: _showFilter,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Text('$count ${count == 1 ? 'ITEM' : 'ITEMS'}', style: eyebrow(context)),
                  const Spacer(),
                  Text(service.lastSynced == null ? 'NOT SYNCED YET' : 'END-TO-END ENCRYPTED', style: eyebrow(context)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _filter = _Filter.values[i]),
                children: [for (final f in _Filter.values) _page(service, f)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The toolbar capsule growing into a glass menu, and shrinking back into it on close.
class _MorphMenu extends StatelessWidget {
  const _MorphMenu({required this.anchor, required this.animation});

  final Rect anchor;
  final Animation<double> animation;

  static const _items = [
    ('generator', Icons.casino_outlined, 'Generator'),
    ('health', Icons.health_and_safety_outlined, 'Vault health'),
    ('settings', Icons.settings_outlined, 'Settings'),
    ('lock', Icons.lock_outline, 'Lock now'),
  ];

  @override
  Widget build(BuildContext context) {
    const width = 248.0;
    final height = _items.length * 58.0 + 20;
    final target = Rect.fromLTWH(anchor.right - width, anchor.top, width, height);
    final grow = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final reveal = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.4, 1, curve: Curves.easeOut),
      reverseCurve: const Interval(0.5, 1, curve: Curves.easeIn),
    );
    final menu = OverflowBox(
      alignment: Alignment.topRight,
      minWidth: width,
      maxWidth: width,
      minHeight: height,
      maxHeight: height,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(children: [
            for (final (value, icon, label) in _items)
              ListTile(
                minTileHeight: 58,
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(context, value),
              ),
          ]),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: grow,
      builder: (context, child) {
        final t = grow.value;
        final rect = Rect.lerp(anchor, target, t)!;
        final radius = ui.lerpDouble(anchor.height / 2, 26, t)!;
        return Stack(children: [
          Positioned.fromRect(
            rect: rect,
            child: Glass(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
              blur: 26,
              tint: 0.08,
              fill: const Color(0x66000000),
              child: ClipRect(child: FadeTransition(opacity: reveal, child: child)),
            ),
          ),
        ]);
      },
      child: menu,
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.entry);

  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final scheme = Theme.of(context).colorScheme;
    final subtitle = entry.sharedWithMe
        ? 'Shared by ${entry.sharedBy}'
        : item.type == ItemType.note
        ? item.notes.split('\n').first
        : item.username;
    return ListTile(
      leading: ItemAvatar(item),
      title: Text(item.title.isEmpty ? 'Untitled' : item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.favorite) Icon(Icons.star, size: 18, color: scheme.primary),
          if (entry.sharedWithMe) const Icon(Icons.people_outline, size: 18),
          if (entry.inConflict)
            Icon(Icons.call_split, size: 18, color: scheme.error)
          else if (!entry.synced)
            Icon(Icons.cloud_upload_outlined, size: 18, color: scheme.outline),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(id: item.id))),
    );
  }
}

class _NewItemDialog extends StatelessWidget {
  const _NewItemDialog();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget option(IconData icon, String title, String subtitle, ItemType type) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
          leading: Icon(icon, size: 26),
          title: Text(title, style: text.titleMedium),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pop(context, type),
        );
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Glass(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(28))),
          blur: 28,
          tint: 0.09,
          child: Material(
            type: MaterialType.transparency,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'New', style: text.headlineSmall),
                  TextSpan(text: '  item', style: serifAccent(context, size: 18)),
                ])),
              ),
              option(Icons.password, 'Login', 'Username, password and website', ItemType.login),
              const Divider(height: 1, indent: 22, endIndent: 22),
              option(Icons.sticky_note_2_outlined, 'Secure note', 'Any text you want to keep private', ItemType.note),
              const SizedBox(height: 10),
            ]),
          ),
        ),
      ),
    );
  }
}
