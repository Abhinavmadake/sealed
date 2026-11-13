import '../../models/vault_item.dart';
import 'strength.dart';

class HealthReport {
  HealthReport(this.weak, this.reused, this.checked);

  final List<(VaultItem, StrengthResult)> weak;
  final List<List<VaultItem>> reused;
  final int checked;

  int get reusedCount => reused.fold(0, (n, g) => n + g.length);

  int score(int breached) {
    if (checked == 0) return 100;
    final bad = {...weak.map((w) => w.$1.id), ...reused.expand((g) => g.map((i) => i.id))}.length + breached;
    return (100 * (1 - bad / checked)).clamp(0, 100).round();
  }
}

HealthReport analyseVault(Iterable<VaultItem> items) {
  final logins = items.where((i) => i.type == ItemType.login && i.password.isNotEmpty).toList();
  final weak = <(VaultItem, StrengthResult)>[];
  final byPassword = <String, List<VaultItem>>{};
  for (final item in logins) {
    final s = estimateStrength(item.password);
    if (!s.acceptable) weak.add((item, s));
    byPassword.putIfAbsent(item.password, () => []).add(item);
  }
  final reused = byPassword.values.where((g) => g.length > 1).toList();
  return HealthReport(weak, reused, logins.length);
}
