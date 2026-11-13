import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../services/vault_service.dart';
import 'login_screen.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/stipple.dart';
import '../widgets/topo.dart';
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
    final host = Uri.tryParse(_server)?.authority ?? _server;
    final display = text.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      height: 1.12,
      color: scheme.onSurface,
    );
    return Backdrop(
      behind: const [
        Positioned.fill(child: TopoBackground(seed: 2, focus: Alignment(0.1, -0.3), peak: 1.5, levels: 26)),
        Positioned.fill(child: _Vignette(center: Alignment(0, -0.3))),
        Positioned(left: 0, right: 0, bottom: 0, height: 420, child: _BottomScrim()),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '-SEALED',
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 2.4),
                        ),
                        const Spacer(),
                        _ServerPill(host: host, reachable: _reachable, onTap: _editServer),
                      ],
                    ),
                    const Expanded(
                      child: Padding(padding: EdgeInsets.symmetric(vertical: 24, horizontal: 36), child: StippleLock()),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'A PASSWORD MANAGER THAT '),
                          TextSpan(
                            text: 'cannot read',
                            style: serifAccent(
                              context,
                              size: (display?.fontSize ?? 28) + 2,
                            ).copyWith(decoration: TextDecoration.underline, decorationThickness: 0.8),
                          ),
                          const TextSpan(text: ' YOUR PASSWORDS.'),
                        ],
                      ),
                      style: display,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Everything is encrypted on this device before it is synced. The server only ever stores ciphertext.',
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen(server: _server))),
                      child: const Text('Create account'),
                    ),
                    const SizedBox(height: 10),
                    GlassButton(
                      onPressed: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(server: _server))),
                      child: const Text('Sign in'),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'ARGON2ID  ·  XCHACHA20-POLY1305  ·  X25519',
                      textAlign: TextAlign.center,
                      style: eyebrow(context),
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

class _Vignette extends StatelessWidget {
  const _Vignette({required this.center});

  final Alignment center;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: center,
            radius: 0.55,
            colors: [bg.withValues(alpha: 0.92), bg.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.82), bg.withValues(alpha: 0.9)],
            stops: const [0, 0.4, 1],
          ),
        ),
      ),
    );
  }
}

class _ServerPill extends StatelessWidget {
  const _ServerPill({required this.host, required this.reachable, required this.onTap});

  final String host;
  final bool? reachable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    final dot = switch (reachable) {
      null => Graphite.chalk.withValues(alpha: 0.35),
      true => const Color(0xFF8FBF86),
      false => const Color(0xFFE58A73),
    };
    return Semantics(
      button: true,
      label: reachable == false ? 'Server unreachable: $host' : 'Server: $host',
      child: Glass(
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Text(
                    reachable == false ? 'Unreachable · $host' : host,
                    style: label?.copyWith(color: Graphite.chalk.withValues(alpha: 0.75)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
