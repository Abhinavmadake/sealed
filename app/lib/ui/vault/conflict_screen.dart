import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sync/vault_repository.dart';
import '../../models/vault_item.dart';
import '../../services/vault_service.dart';
import '../widgets/common.dart';

class ConflictScreen extends StatefulWidget {
  const ConflictScreen({super.key, required this.id});

  final String id;

  @override
  State<ConflictScreen> createState() => _ConflictScreenState();
}

class _ConflictScreenState extends State<ConflictScreen> {
  ConflictView? _view;
  final Map<String, bool> _useMine = {};
  bool _reveal = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<VaultService>().conflict(widget.id).then((v) {
      if (!mounted) return;
      setState(() {
        _view = v;
        for (final f in v?.fields ?? const <String>[]) {
          _useMine[f] = true;
        }
      });
    });
  }

  String _show(String field, Object? value) {
    final s = '${value ?? ''}';
    if (s.isEmpty) return '(empty)';
    if (field == 'password' && !_reveal) return '•' * 12;
    return s;
  }

  Future<void> _save() async {
    final view = _view!;
    final chosen = {
      ...view.mine,
      for (final f in view.fields) f: _useMine[f]! ? view.mine[f] : view.theirs[f],
      'modified': DateTime.now().toUtc().toIso8601String(),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<VaultService>().resolve(widget.id, chosen);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (view == null) {
      return Scaffold(appBar: AppBar(title: const Text('Resolve conflict')), body: const Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    Widget option(String field, bool mine) {
      final selected = _useMine[field] == mine;
      return Card(
        elevation: 0,
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: ListTile(
          leading: Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? scheme.primary : null),
          title: Text(mine ? 'This device' : 'Other device'),
          subtitle: Text(_show(field, mine ? view.mine[field] : view.theirs[field]),
              style: TextStyle(fontFamily: field == 'password' ? 'monospace' : null)),
          onTap: () => setState(() => _useMine[field] = mine),
        ),
      );
    }

    return FormPage(title: 'Resolve conflict', children: [
      const Text('Both devices changed these fields before syncing. Everything else was merged automatically.'),
      gap,
      ErrorText(_error),
      for (final field in view.fields) ...[
        Row(children: [
          Expanded(child: Text(VaultItem.fieldLabels[field] ?? field, style: Theme.of(context).textTheme.titleMedium)),
          if (field == 'password')
            TextButton(onPressed: () => setState(() => _reveal = !_reveal), child: Text(_reveal ? 'Hide' : 'Show')),
        ]),
        const SizedBox(height: 4),
        option(field, true),
        option(field, false),
        gap,
      ],
      BusyButton(label: 'Keep these choices', busy: _busy, onPressed: _save),
    ]);
  }
}
