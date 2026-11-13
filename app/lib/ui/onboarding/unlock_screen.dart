import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/vault_service.dart';
import '../widgets/common.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _unlock() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<VaultService>().unlock(_password.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final service = context.read<VaultService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'This removes the vault from this device. Changes that have not synced yet will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await service.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VaultService>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
              Icon(Icons.lock_outline, size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Vault locked', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(service.email, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 28),
              ErrorText(_error),
              PasswordField(
                controller: _password,
                label: 'Master password',
                autofocus: true,
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 20),
              BusyButton(label: 'Unlock', busyLabel: 'Unlocking…', busy: _busy, onPressed: _unlock),
              const SizedBox(height: 8),
              TextButton(onPressed: _signOut, child: const Text('Not you? Sign out')),
            ]),
          ),
        ),
      ),
    );
  }
}
