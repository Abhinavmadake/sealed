import 'package:flutter/material.dart';

import '../../services/vault_service.dart';
import 'login_screen.dart';
import '../theme.dart';
import '../widgets/elastic.dart';
import '../widgets/glass.dart';
import '../widgets/graphite.dart';
import '../widgets/topo.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final String _server = defaultServer;

  void _register() => Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen(server: _server)));

  void _login() => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(server: _server)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final focus = wide ? const Alignment(0.42, 0.05) : const Alignment(0, -0.3);

    final display = (wide ? text.displaySmall : text.headlineMedium)?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      height: 1.12,
      color: scheme.onSurface,
    );
    final headline = Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'A PASSWORD MANAGER THAT '),
        TextSpan(
          text: 'cannot read',
          style: serifAccent(context, size: (display?.fontSize ?? 28) + 2)
              .copyWith(decoration: TextDecoration.underline, decorationThickness: 0.8),
        ),
        const TextSpan(text: ' YOUR PASSWORDS.'),
      ]),
      style: display,
    );
    final lede = Text(
      'Everything is encrypted on this device before it is synced. The server only ever stores ciphertext.',
      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
    );
    final crypto = Text('ARGON2ID  ·  XCHACHA20-POLY1305  ·  X25519', style: eyebrow(context));
    const lock = GrainLock();

    final topBar = Row(children: [
      Text('-SEALED', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 2.4)),
    ]);

    Widget actions({required bool stacked}) {
      final create = FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 26)),
        onPressed: _register,
        child: const Text('Create account'),
      );
      final signIn = GlassButton(height: 46, blur: 0, onPressed: _login, child: const Text('Sign in'));
      return stacked
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [create, const SizedBox(height: 10), signIn])
          : Row(children: [create, const SizedBox(width: 12), signIn]);
    }

    final body = wide
        ? Row(children: [
            Expanded(
              flex: 5,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: headline),
                const SizedBox(height: 20),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: lede),
                const SizedBox(height: 30),
                actions(stacked: false),
                const SizedBox(height: 30),
                crypto,
              ]),
            ),
            const Expanded(flex: 6, child: Padding(padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24), child: lock)),
          ])
        : null;

    Widget narrow(BoxConstraints box) => Stack(children: [
          const Positioned(left: 20, right: 20, top: 76, bottom: 380, child: lock),
          Positioned.fill(
            child: ElasticStretch(
              child: SizedBox(
                height: box.maxHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    topBar,
                    const Spacer(),
                    headline,
                    const SizedBox(height: 14),
                    lede,
                    const SizedBox(height: 24),
                    actions(stacked: true),
                    const SizedBox(height: 18),
                    Center(child: crypto),
                  ]),
                ),
              ),
            ),
          ),
        ]);

    return Backdrop(
      behind: [
        Positioned.fill(child: TopoBackground(seed: 2, focus: focus, peak: 1.5, levels: 26)),
        Positioned.fill(child: _Vignette(center: focus)),
        Positioned.fill(child: LightBeam(toward: focus)),
        if (!wide) const Positioned(left: 0, right: 0, bottom: 0, height: 420, child: _BottomScrim()),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1200 : 460),
              child: wide
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(40, 20, 40, 32),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        topBar,
                        Expanded(child: body!),
                      ]),
                    )
                  : LayoutBuilder(builder: (context, box) => narrow(box)),
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
