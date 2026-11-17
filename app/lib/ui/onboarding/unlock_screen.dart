import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/biometric/biometric_key_store.dart';
import '../../services/vault_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/graphite.dart';
import '../widgets/topo.dart';

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

  @override
  void initState() {
    super.initState();
    if (context.read<VaultService>().biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }
  }

  // Not tied to _busy: the plugin never reports the prompt's negative button, so this may not return.
  Future<void> _biometric() async {
    setState(() => _error = null);
    try {
      await context.read<VaultService>().unlockWithBiometric();
    } on BiometricCancelled {
      // Fall back to the password field.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _signOut() async {
    final service = context.read<VaultService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('This removes the vault from this device. Changes that have not synced yet will be lost.'),
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
    final text = Theme.of(context).textTheme;
    return Backdrop(
      behind: const [
        Positioned.fill(child: TopoBackground(seed: 6, focus: Alignment(0, -0.45), peak: 1.6, levels: 24)),
        Positioned.fill(child: LightBeam(toward: Alignment(0, -0.1))),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                padding: const EdgeInsets.all(24),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 300, child: Padding(padding: EdgeInsets.all(4), child: GrainLock())),
                  const SizedBox(height: 28),
                  Text('LOCKED', textAlign: TextAlign.center, style: eyebrow(context)),
                  const SizedBox(height: 6),
                  Text(service.email, textAlign: TextAlign.center, style: text.headlineSmall),
                  const SizedBox(height: 28),
                  ErrorText(_error),
                  PasswordField(
                    controller: _password,
                    label: 'Master password',
                    autofocus: !service.biometricEnabled,
                    onSubmitted: (_) => _unlock(),
                  ),
                  const SizedBox(height: 20),
                  BusyButton(label: 'Unlock', busyLabel: 'Unlocking…', busy: _busy, onPressed: _unlock),
                  if (service.biometricEnabled) ...[
                    const SizedBox(height: 10),
                    GlassButton(
                      blur: 0,
                      onPressed: _busy ? null : _biometric,
                      icon: const Icon(Icons.fingerprint),
                      child: const Text('Use fingerprint'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _signOut,
                    child: Text('Not you? Sign out', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
