import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/crypto/sealed_crypto.dart';
import 'core/health/strength.dart';
import 'core/store/local_store.dart';
import 'core/store/store_factory.dart';
import 'services/vault_service.dart';
import 'ui/generator/generator_screen.dart';
import 'ui/onboarding/recovery_key_screen.dart';
import 'ui/onboarding/unlock_screen.dart';
import 'ui/onboarding/welcome_screen.dart';
import 'ui/theme.dart';
import 'ui/vault/vault_screen.dart';
import 'ui/widgets/stipple.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SealedApp());
}

class SealedApp extends StatefulWidget {
  const SealedApp({super.key});

  @override
  State<SealedApp> createState() => _SealedAppState();
}

class _SealedAppState extends State<SealedApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final Future<VaultService> _boot = _start();
  VaultStatus? _lastStatus;

  Future<VaultService> _start() async {
    final crypto = await SealedCrypto.init();
    dictionaryWords = (await loadWordlist()).toSet();
    final db = await openSealedDatabase();
    final service = VaultService(crypto, LocalStore(db));
    service.addListener(() {
      if (service.status != _lastStatus) {
        _lastStatus = service.status;
        _navigator.currentState?.popUntil((r) => r.isFirst);
      }
    });
    await service.start();
    return service;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<VaultService>(
        future: _boot,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            const ink = Graphite.chalk;
            return Directionality(
              textDirection: TextDirection.ltr,
              child: ColoredBox(
                color: Graphite.ink,
                child: Center(
                  child: snapshot.hasError
                      ? Text('Could not start: ${snapshot.error}', style: TextStyle(color: ink))
                      : SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 1.5, color: ink)),
                ),
              ),
            );
          }
          final service = snapshot.data!;
          return ChangeNotifierProvider.value(
            value: service,
            child: Listener(
              onPointerDown: (_) => service.touch(),
              child: MaterialApp(
                title: 'Sealed',
                debugShowCheckedModeBanner: false,
                navigatorKey: _navigator,
                theme: buildTheme(Brightness.dark),
                themeMode: ThemeMode.dark,
                home: const _Root(),
                builder: (context, child) => Stack(children: [child!, const Positioned.fill(child: GrainOverlay())]),
              ),
            ),
          );
        },
      );
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VaultService>();
    return switch (service.status) {
      VaultStatus.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      VaultStatus.noAccount => const WelcomeScreen(),
      VaultStatus.locked => const UnlockScreen(),
      VaultStatus.unlocked => service.pendingRecoveryKey != null
          ? RecoveryKeyScreen(recoveryKey: service.pendingRecoveryKey!)
          : const VaultScreen(),
    };
  }
}
