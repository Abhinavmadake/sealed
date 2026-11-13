import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../services/vault_service.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String _server = defaultServer;
  bool? _reachable;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _reachable = null);
    final ok = await ApiClient(_server, timeout: const Duration(seconds: 5)).health();
    if (mounted) setState(() => _reachable = ok);
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: _server);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server address'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'http://10.0.2.2:8000'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) {
      setState(() => _server = value);
      _check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Spacer(),
                Icon(Icons.shield_moon_outlined, size: 72, color: scheme.primary),
                const SizedBox(height: 16),
                Text('Sealed', textAlign: TextAlign.center, style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  'A password manager that cannot read your passwords.',
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                Text(
                  'Everything is encrypted on this device before it is synced. '
                  'The server only ever stores ciphertext.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => RegisterScreen(server: _server))),
                  child: const Text('Create account'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(server: _server))),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _editServer,
                  icon: Icon(
                    _reachable == null ? Icons.sync : (_reachable! ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
                    size: 18,
                    color: _reachable == false ? scheme.error : null,
                  ),
                  label: Text(
                    _reachable == false ? 'Server unreachable: $_server' : 'Server: $_server',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
