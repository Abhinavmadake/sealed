import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/health/strength.dart';
import '../../models/vault_item.dart';
import '../../services/vault_service.dart';
import '../sharing/share_screen.dart';
import '../widgets/common.dart';
import '../widgets/panel.dart';
import 'conflict_screen.dart';
import 'item_edit_screen.dart';

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  bool _reveal = false;

  Future<void> _delete(VaultService service, VaultItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${item.title}"?'),
        content: const Text('It will be removed from all your devices and from anyone you shared it with.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await service.delete(item.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VaultService>();
    final entry = service.entry(widget.id);
    if (entry == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This item is no longer in your vault.')));
    }
    final item = entry.item;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget field(String label, String value, {bool secret = false, bool mono = false}) {
      if (value.isEmpty) return const SizedBox.shrink();
      final shown = secret && !_reveal ? '•' * 12 : value;
      return ListTile(
        title: Text(label, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
        subtitle: Text(
          shown,
          style: text.bodyLarge?.copyWith(fontFamily: secret || mono ? 'monospace' : null),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (secret)
            IconButton(
              tooltip: _reveal ? 'Hide' : 'Show',
              icon: Icon(_reveal ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _reveal = !_reveal),
            ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () => copySecret(context, value, label),
          ),
        ]),
      );
    }

    final login = item.type == ItemType.login;
    final fields = <Widget>[
      if (login && item.username.isNotEmpty) field('Username', item.username),
      if (login && item.password.isNotEmpty)
        Column(mainAxisSize: MainAxisSize.min, children: [
          field('Password', item.password, secret: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: StrengthMeter(estimateStrength(item.password)),
          ),
        ]),
      if (login && item.url.isNotEmpty) field('Website', item.url),
      if (item.notes.isNotEmpty) field('Notes', item.notes),
    ];

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (entry.canWrite)
            IconButton(
              tooltip: item.favorite ? 'Remove from favourites' : 'Add to favourites',
              icon: Icon(item.favorite ? Icons.star : Icons.star_border),
              onPressed: () => service.save(item.copyWith(favorite: !item.favorite)),
            ),
          if (entry.isOwner)
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.person_add_alt),
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ShareScreen(itemId: item.id))),
            ),
          if (entry.canWrite)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ItemEditScreen(existing: item))),
            ),
          if (entry.isOwner)
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(service, item)),
        ],
      ),
      body: ListView(padding: listInsets(context), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 20),
          child: Row(children: [
            Transform.scale(scale: 1.3, child: ItemAvatar(item)),
            const SizedBox(width: 20),
            Expanded(child: Text(item.title.isEmpty ? 'Untitled' : item.title, style: text.headlineSmall)),
          ]),
        ),
        if (entry.inConflict)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: scheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.call_split, color: scheme.onErrorContainer),
                title: Text('Changed on two devices', style: TextStyle(color: scheme.onErrorContainer)),
                subtitle: Text('Choose which version to keep', style: TextStyle(color: scheme.onErrorContainer)),
                trailing: Icon(Icons.chevron_right, color: scheme.onErrorContainer),
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ConflictScreen(id: item.id))),
              ),
            ),
          ),
        if (entry.sharedWithMe)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoCard(
              icon: Icons.people_outline,
              text: 'Shared with you by ${entry.sharedBy}. '
                  '${entry.canWrite ? 'You can edit it.' : 'You can view it but not change it.'}\n'
                  'Their fingerprint: ${service.crypto.fingerprint(entry.remote!.grantedByPublicKey!)}',
            ),
          ),
        if (fields.isNotEmpty) PanelGroup(children: fields),
        const SizedBox(height: 12),
        Panel(
          child: ListTile(
            dense: true,
            leading: Icon(entry.synced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined, size: 20),
            title: Text(entry.synced ? 'Synced' : 'Waiting to sync'),
            subtitle: Text('Last changed ${_when(item.modifiedAt)}'),
          ),
        ),
      ]),
    );
  }

  String _when(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
