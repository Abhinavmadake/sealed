import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sync/vault_repository.dart';
import '../../models/vault_item.dart';
import '../../services/vault_service.dart';
import '../generator/generator_screen.dart';
import '../health/health_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/common.dart';
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
  bool _searching = false;
  _Filter _filter = _Filter.all;

  bool _matches(VaultEntry e) {
    final item = e.item;
    final ok = switch (_filter) {
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
    final type = await showModalBottomSheet<ItemType>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Login'),
            subtitle: const Text('Username, password and website'),
            onTap: () => Navigator.pop(context, ItemType.login),
          ),
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: const Text('Secure note'),
            subtitle: const Text('Any text you want to keep private'),
            onTap: () => Navigator.pop(context, ItemType.note),
          ),
        ]),
      ),
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
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('This device was signed out by the server. Enter your current master password to keep syncing.'),
            gap,
            ErrorText(error),
            PasswordField(controller: controller, label: 'Master password', autofocus: true),
          ]),
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
      icon: Badge(isLabelVisible: s.pendingCount > 0, label: Text('${s.pendingCount}'), child: Icon(icon, color: color)),
      onPressed: s.sessionExpired ? () => _reauthenticate(s) : s.sync,
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VaultService>();
    final scheme = Theme.of(context).colorScheme;
    final visible = service.entries.where(_matches).toList();
    final conflicts = service.entries.where((e) => e.inConflict).length;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search', border: InputBorder.none),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Vault'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _search.clear();
            }),
          ),
          _syncButton(service),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'generator' => Navigator.push(context, MaterialPageRoute(builder: (_) => const GeneratorScreen())),
              'health' => Navigator.push(context, MaterialPageRoute(builder: (_) => const HealthScreen())),
              'settings' => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              _ => service.lock(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'generator', child: ListTile(leading: Icon(Icons.casino_outlined), title: Text('Generator'))),
              PopupMenuItem(value: 'health', child: ListTile(leading: Icon(Icons.health_and_safety_outlined), title: Text('Vault health'))),
              PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
              PopupMenuItem(value: 'lock', child: ListTile(leading: Icon(Icons.lock_outline), title: Text('Lock now'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: Column(children: [
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
            content: Text('$conflicts item(s) were changed on two devices and need your choice.',
                style: TextStyle(color: scheme.onErrorContainer)),
            leading: Icon(Icons.call_split, color: scheme.onErrorContainer),
            actions: [
              TextButton(
                onPressed: () {
                  final first = service.entries.firstWhere((e) => e.inConflict);
                  Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ItemDetailScreen(id: first.item.id)));
                },
                child: const Text('Review'),
              ),
            ],
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            for (final f in _Filter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(switch (f) {
                    _Filter.all => 'All',
                    _Filter.favorites => 'Favourites',
                    _Filter.logins => 'Logins',
                    _Filter.notes => 'Notes',
                    _Filter.shared => 'Shared with me',
                  }),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: service.sync,
            child: visible.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Icon(Icons.inventory_2_outlined, size: 56, color: scheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      service.entries.isEmpty ? 'Your vault is empty.\nTap New to add a login.' : 'Nothing matches.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: visible.length,
                    itemBuilder: (context, i) => _EntryTile(visible[i]),
                  ),
          ),
        ),
      ]),
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
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (item.favorite) Icon(Icons.star, size: 18, color: scheme.primary),
        if (entry.sharedWithMe) const Icon(Icons.people_outline, size: 18),
        if (entry.inConflict)
          Icon(Icons.call_split, size: 18, color: scheme.error)
        else if (!entry.synced)
          Icon(Icons.cloud_upload_outlined, size: 18, color: scheme.outline),
      ]),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(id: item.id))),
    );
  }
}
