import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/dto.dart';
import '../../services/vault_service.dart';
import '../widgets/common.dart';
import '../widgets/panel.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<SessionInfo>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await context.read<VaultService>().sessions();
      if (mounted) setState(() => _sessions = s);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _end(SessionInfo s) async {
    try {
      await context.read<VaultService>().endSession(s.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 2) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} minutes ago';
    if (d.inDays < 1) return '${d.inHours} hours ago';
    return '${d.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Signed-in devices')),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: listInsets(context, top: 8), children: [
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: ErrorText(_error)),
            if (_sessions == null && _error == null) const LinearProgressIndicator(),
            if (_sessions != null && _sessions!.isNotEmpty)
            PanelGroup(dividerIndent: 72, children: [
            for (final s in _sessions!)
              ListTile(
                leading: Icon(s.current ? Icons.smartphone : Icons.devices_other),
                title: Text(s.current ? '${s.deviceName} (this device)' : s.deviceName),
                subtitle: Text('Last active ${_ago(s.lastSeenAt)}'),
                trailing: s.current
                    ? null
                    : TextButton(onPressed: () => _end(s), child: const Text('Sign out')),
              ),
            ]),
          ]),
        ),
      );
}
