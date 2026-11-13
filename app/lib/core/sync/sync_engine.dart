import '../../models/vault_item.dart';
import '../api/api_client.dart';
import '../api/dto.dart';
import '../store/local_store.dart';
import 'merge.dart';
import 'vault_repository.dart';

class SyncReport {
  int pulled = 0;
  int pushed = 0;
  bool offline = false;
  final Set<String> conflicts = {};
  final List<String> notices = [];
}

class SyncEngine {
  SyncEngine(this.api, this.repo);

  final ApiClient api;
  final VaultRepository repo;
  Future<SyncReport>? _running;

  LocalStore get _store => repo.store;

  Future<SyncReport> sync() => _running ??= _sync().whenComplete(() => _running = null);

  Future<SyncReport> _sync() async {
    final report = SyncReport();
    try {
      await _pull(report);
      await _push(report);
    } on OfflineException {
      report.offline = true;
    }
    return report;
  }

  Future<void> _pull(SyncReport report) async {
    final (revision, changes) = await api.sync(await _store.cursor());
    for (final remote in changes) {
      final pending = await _store.pendingFor(remote.id);
      if (remote.deleted) {
        await _store.removeItem(remote.id);
        if (pending?.op == PendingOp.upsert) {
          final title = await repo.keepAsCopy(pending!);
          report.notices.add('"$title" was removed or unshared, so your unsynced changes were kept as a new item.');
        } else if (pending != null) {
          await _store.removePending(remote.id);
        }
      } else {
        await _store.putItem(remote);
      }
      report.pulled++;
    }
    await _store.setCursor(revision);
  }

  Future<void> _push(SyncReport report) async {
    final queue = (await _store.pending()).values.toList()..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    for (final change in queue) {
      if (change.inConflict) {
        report.conflicts.add(change.id);
        continue;
      }
      if (change.op == PendingOp.delete) {
        await _pushDelete(change, report);
      } else {
        await _pushUpsert(change, report);
      }
    }
  }

  Future<void> _pushDelete(PendingChange change, SyncReport report) async {
    try {
      await api.deleteItem(change.id, change.baseRevision!);
      await _store.removeItem(change.id);
      report.pushed++;
    } on ConflictException catch (e) {
      final current = e.current;
      if (current != null && !current.deleted) await _store.putItem(current);
      report.notices.add('An item changed on another device, so it was not deleted.');
    } on ApiException catch (e) {
      if (e.status != 404 && e.status != 403) rethrow;
      await _store.removeItem(change.id);
    }
    await _store.removePending(change.id);
  }

  Future<void> _pushUpsert(PendingChange change, SyncReport report, [int attempt = 0]) async {
    final codec = repo.codec;
    final data = codec.openLocal('pending', change.id, change.payload!);
    try {
      final key = change.isNew
          ? codec.unwrapOwn(change.id, change.wrappedKey!)
          : await _store.item(change.id).then((r) => r == null ? null : codec.keyFor(r));
      if (key == null) {
        final title = await repo.keepAsCopy(change);
        report.notices.add('"$title" is no longer available, so your changes were kept as a new item.');
        return;
      }
      final blob = codec.sealFor(key, change.id, data);
      key.dispose();
      final result = await api.putItem(
        change.id,
        blob,
        baseRevision: change.baseRevision,
        wrappedKey: change.isNew ? change.wrappedKey : null,
      );
      await _store.putItem(result);
      await _store.removePending(change.id);
      report.pushed++;
    } on ConflictException catch (e) {
      await _rebase(change, data, e.current, report, attempt);
    } on ApiException catch (e) {
      if (e.status != 403 && e.status != 404) rethrow;
      final title = await repo.keepAsCopy(change);
      report.notices.add(e.status == 403
          ? 'You can only view "$title", so your changes were kept as a new item.'
          : '"$title" is no longer available, so your changes were kept as a new item.');
    }
  }

  Future<void> _rebase(
    PendingChange change,
    Map<String, dynamic> mine,
    RemoteItem? current,
    SyncReport report,
    int attempt,
  ) async {
    if (current == null || current.deleted) {
      if (current != null) await _store.removeItem(change.id);
      final title = await repo.keepAsCopy(change);
      report.notices.add('"$title" was deleted elsewhere, so your changes were kept as a new item.');
      return;
    }
    await _store.putItem(current);
    final codec = repo.codec;
    final theirs = codec.openRemote(current);
    final base = change.base == null ? null : codec.openLocal('base', change.id, change.base!);
    final merge = threeWayMerge(base, mine, theirs, fields: VaultItem.mergeFields);
    if (merge.clean && _sameContent(merge.merged, theirs)) {
      await _store.removePending(change.id);
      return;
    }
    final rebased = change.copyWith(
      payload: codec.sealLocal('pending', change.id, merge.merged),
      base: codec.sealLocal('base', change.id, theirs),
      baseRevision: current.itemRevision,
      conflictFields: merge.conflicts,
      dropWrappedKey: true,
    );
    await _store.putPending(rebased);
    if (!merge.clean) {
      report.conflicts.add(change.id);
    } else if (attempt < 3) {
      await _pushUpsert(rebased, report, attempt + 1);
    }
  }

  bool _sameContent(Map<String, dynamic> a, Map<String, dynamic> b) =>
      VaultItem.mergeFields.every((f) => a[f] == b[f]);
}
