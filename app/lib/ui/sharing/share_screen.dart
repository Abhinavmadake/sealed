import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/dto.dart';
import '../../services/vault_service.dart';
import '../widgets/common.dart';

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, required this.itemId});

  final String itemId;

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final _email = TextEditingController();
  List<GrantInfo>? _grants;
  UserInfo? _found;
  bool _foundPinned = false;
  String _permission = 'read';
  bool _busy = false;
  String? _error;

  VaultService get _service => context.read<VaultService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
        final grants = await _service.sharing.grants(widget.itemId);
        if (mounted) setState(() => _grants = grants);
      });

  Future<void> _find() => _run(() async {
        final email = _email.text.trim().toLowerCase();
        if (email == _service.email) throw StateError('That is you');
        final user = await _service.sharing.findUser(email);
        if (user == null) throw StateError('Nobody with that email uses Sealed yet');
        final pinned = await _service.sharing.isPinned(user);
        if (mounted) {
          setState(() {
            _found = user;
            _foundPinned = pinned;
          });
        }
      });

  Future<void> _share() => _run(() async {
        await _service.share(widget.itemId, _found!, _permission);
        _email.clear();
        setState(() => _found = null);
        await _load();
      });

  Future<void> _revoke(GrantInfo g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop sharing with ${g.user.email}?'),
        content: const Text(
          'They lose access straight away and the item gets a new key, so future changes stay private. '
          'Anything they already saw may have been copied, so consider changing the password too.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop sharing')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _service.revoke(widget.itemId, g.user.id);
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = _found;
    final others = (_grants ?? const <GrantInfo>[]).where((g) => g.permission != 'owner').toList();
    return FormPage(title: 'Share', children: [
      ErrorText(_error),
      Text('People with access', style: Theme.of(context).textTheme.titleMedium),
      if (_grants == null && _busy) const LinearProgressIndicator(),
      if (_grants != null && others.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Only you.')),
      for (final g in others)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(g.user.email),
          subtitle: Text(g.permission == 'write' ? 'Can edit' : 'Can view'),
          trailing: IconButton(
            tooltip: 'Stop sharing',
            icon: const Icon(Icons.person_remove_outlined),
            onPressed: _busy ? null : () => _revoke(g),
          ),
        ),
      const Divider(height: 32),
      Text('Add someone', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Their Sealed email'),
            onSubmitted: (_) => _find(),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonal(onPressed: _busy ? null : _find, child: const Text('Find')),
      ]),
      if (found != null) ...[
        gap,
        Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(found.email, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text('Security fingerprint'),
              const SizedBox(height: 4),
              SelectableText(
                _service.crypto.fingerprint(found.publicKey),
                key: const Key('fingerprint'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 18, letterSpacing: 1),
              ),
              const SizedBox(height: 12),
              Text(
                _foundPinned
                    ? 'Matches the key you used before.'
                    : 'First time sharing with them. Ask them to read out the fingerprint from their '
                        'Settings screen. If it does not match, someone may be intercepting.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
        ),
        gap,
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'read', icon: Icon(Icons.visibility_outlined), label: Text('Can view')),
            ButtonSegment(value: 'write', icon: Icon(Icons.edit_outlined), label: Text('Can edit')),
          ],
          selected: {_permission},
          onSelectionChanged: (s) => setState(() => _permission = s.first),
        ),
        gap,
        BusyButton(label: 'Share with ${found.email}', busy: _busy, onPressed: _share),
      ],
    ]);
  }
}
