import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/biometric/biometric_key_store.dart';
import '../../services/vault_service.dart';
import '../widgets/common.dart';
import 'change_password_screen.dart';
import 'devices_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _lockChoices = [
    (Duration(minutes: 1), '1 minute'),
    (Duration(minutes: 5), '5 minutes'),
    (Duration(minutes: 15), '15 minutes'),
    (Duration(hours: 1), '1 hour'),
  ];

  static const _clipboardChoices = [
    (Duration(seconds: 15), '15 seconds'),
    (Duration(seconds: 30), '30 seconds'),
    (Duration(seconds: 60), '1 minute'),
    (Duration.zero, 'Never'),
  ];

  Future<void> _pick(BuildContext context, String title, List<(Duration, String)> choices, Duration current,
      ValueChanged<Duration> onPicked) async {
    final picked = await showDialog<Duration>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (d, label) in choices)
            ListTile(
              leading: Icon(d == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(label),
              onTap: () => Navigator.pop(context, d),
            ),
        ],
      ),
    );
    if (picked != null) onPicked(picked);
  }

  String _label(List<(Duration, String)> choices, Duration d) =>
      choices.firstWhere((c) => c.$1 == d, orElse: () => (d, '${d.inSeconds} s')).$2;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VaultService>();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget header(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Text(label, style: text.labelLarge?.copyWith(color: scheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        header('Account'),
        ListTile(leading: const Icon(Icons.person_outline), title: Text(service.email), subtitle: Text(service.record?.serverUrl ?? '')),
        ListTile(
          leading: const Icon(Icons.fingerprint),
          title: const Text('Your security fingerprint'),
          subtitle: SelectableText(service.fingerprint, style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
          isThreeLine: true,
        ),
        header('Security'),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Lock after inactivity'),
          subtitle: Text(_label(_lockChoices, service.autoLock)),
          onTap: () => _pick(context, 'Lock after', _lockChoices, service.autoLock,
              (d) => service.updateSettings(autoLock: d)),
        ),
        ListTile(
          leading: const Icon(Icons.content_paste_off_outlined),
          title: const Text('Clear copied passwords'),
          subtitle: Text(_label(_clipboardChoices, service.clipboardClear)),
          onTap: () => _pick(context, 'Clear clipboard after', _clipboardChoices, service.clipboardClear,
              (d) => service.updateSettings(clipboardClear: d)),
        ),
        if (service.biometricAvailable)
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Unlock with fingerprint'),
            subtitle: const Text('Your master password still works and is needed to sign in.'),
            value: service.biometricEnabled,
            onChanged: (on) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                on ? await service.enableBiometric() : await service.disableBiometric();
              } on BiometricCancelled {
                return;
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
              }
            },
          ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Change master password'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.devices_outlined),
          title: const Text('Signed-in devices'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesScreen())),
        ),
        ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Lock now'), onTap: service.lock),
        ListTile(
          leading: Icon(Icons.logout, color: scheme.error),
          title: Text('Sign out of this device', style: TextStyle(color: scheme.error)),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Sign out?'),
                content: Text(service.pendingCount > 0
                    ? '${service.pendingCount} change(s) have not synced yet and will be lost.'
                    : 'The vault will be removed from this device. It stays safe on your other devices.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
                ],
              ),
            );
            if (ok == true) await service.signOut();
          },
        ),
        header('About'),
        const ListTile(
          leading: Icon(Icons.shield_outlined),
          title: Text('How Sealed protects you'),
          subtitle: Text(
            'Your master password is stretched with Argon2id on this device. Items are encrypted with '
            'XChaCha20-Poly1305 before they leave it, and shared items are re-encrypted for each person '
            'with X25519. The server stores ciphertext only and cannot read your vault.',
          ),
          isThreeLine: true,
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
