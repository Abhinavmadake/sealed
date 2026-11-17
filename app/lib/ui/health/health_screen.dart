import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/health/breach.dart';
import '../../core/health/strength.dart';
import '../../core/health/vault_health.dart';
import '../../models/vault_item.dart';
import '../../services/vault_service.dart';
import '../vault/item_detail_screen.dart';
import '../widgets/common.dart';
import '../widgets/panel.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  final _checker = BreachChecker();
  Map<String, int>? _breached;
  bool _checking = false;
  String? _error;

  Future<void> _check(List<VaultItem> items) async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final found = <String, int>{};
    try {
      for (final item in items) {
        final n = await _checker.timesSeen(item.password);
        if (n > 0) found[item.id] = n;
      }
      if (mounted) setState(() => _breached = found);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the breach database. Check your connection.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VaultService>();
    final items = service.entries.map((e) => e.item).toList();
    final report = analyseVault(items);
    final logins = items.where((i) => i.type == ItemType.login && i.password.isNotEmpty).toList();
    final score = report.score(_breached?.keys ?? const []);
    final scheme = Theme.of(context).colorScheme;
    final color = score >= 80
        ? StrengthMeter.colorFor(Strength.strong)
        : score >= 50
            ? StrengthMeter.colorFor(Strength.fair)
            : scheme.error;

    Widget tile(VaultItem item, String why) => ListTile(
          leading: ItemAvatar(item),
          title: Text(item.title),
          subtitle: Text(why),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(id: item.id))),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Vault health')),
      body: ListView(padding: listInsets(context), children: [
        Panel(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(children: [
        Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: Stack(fit: StackFit.expand, children: [
              CircularProgressIndicator(value: score / 100, strokeWidth: 3, color: color,
                  backgroundColor: color.withValues(alpha: 0.15)),
              Center(child: Text('$score', style: Theme.of(context).textTheme.displaySmall)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text('${report.checked} passwords checked')),
        const SizedBox(height: 16),
        Column(children: [
            const InfoCard(
              icon: Icons.privacy_tip_outlined,
              text: 'The breach check uses Have I Been Pwned. Only the first 5 characters of each '
                  "password's SHA-1 hash are sent, never the password, and the matching happens here.",
            ),
            gap,
            ErrorText(_error),
            BusyButton(
              label: _breached == null ? 'Check for breaches' : 'Check again',
              busyLabel: 'Checking…',
              busy: _checking,
              onPressed: logins.isEmpty ? null : () => _check(logins),
            ),
          ]),
          ]),
        ),
        if (_breached != null) ...[
          SectionLabel('Breached (${_breached!.length})'),
          PanelGroup(dividerIndent: 72, children: [
            if (_breached!.isEmpty) const ListTile(title: Text('None of your passwords appear in known breaches.')),
            for (final item in logins.where((i) => _breached!.containsKey(i.id)))
              tile(item, 'Seen ${_breached![item.id]} times in breaches. Change it.'),
          ]),
        ],
        SectionLabel('Weak (${report.weak.length})'),
        PanelGroup(dividerIndent: 72, children: [
          if (report.weak.isEmpty) const ListTile(title: Text('No weak passwords.')),
          for (final (item, s) in report.weak) tile(item, s.warning ?? 'Easy to guess'),
        ]),
        SectionLabel('Reused (${report.reusedCount})'),
        PanelGroup(dividerIndent: 72, children: [
          if (report.reused.isEmpty) const ListTile(title: Text('Every password is unique.')),
          for (final group in report.reused)
            for (final item in group) tile(item, 'Same password as ${group.length - 1} other item(s)'),
        ]),
      ]),
    );
  }
}
