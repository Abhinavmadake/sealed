import 'package:uuid/uuid.dart';

import '../../models/vault_item.dart';
import '../api/dto.dart';
import '../crypto/sealed_crypto.dart';
import '../store/local_store.dart';
import 'vault_codec.dart';

class VaultEntry {
  VaultEntry({required this.item, this.remote, this.pending});

  final VaultItem item;
  final RemoteItem? remote;
  final PendingChange? pending;

  bool get synced => pending == null;
  bool get inConflict => pending?.inConflict ?? false;
  bool get isOwner => remote == null || remote!.isOwner;
  bool get canWrite => remote == null || remote!.canWrite;
  bool get sharedWithMe => remote != null && !remote!.isOwner;
  String? get sharedBy => sharedWithMe ? remote!.grantedByEmail : null;
}

class ConflictView {
  ConflictView(this.mine, this.theirs, this.fields);

  final Map<String, dynamic> mine;
  final Map<String, dynamic> theirs;
  final List<String> fields;
}

/// Local view of the vault: server copies overlaid with queued offline changes.
class VaultRepository {
  VaultRepository(this.store, this.codec);

  final LocalStore store;
  final VaultCodec codec;
  static const _uuid = Uuid();

  String newId() => _uuid.v4();

  Future<List<VaultEntry>> entries() async {
    final remote = await store.items();
    final pending = await store.pending();
    final out = <VaultEntry>[];
    for (final r in remote.values) {
      final p = pending[r.id];
      if (p?.op == PendingOp.delete) continue;
      try {
        final data = p != null ? codec.openLocal('pending', r.id, p.payload!) : codec.openRemote(r);
        out.add(VaultEntry(item: VaultItem.fromJson(r.id, data), remote: r, pending: p));
      } on DecryptionFailed {
        continue;
      }
    }
    for (final p in pending.values) {
      if (remote.containsKey(p.id) || p.op != PendingOp.upsert) continue;
      final data = codec.openLocal('pending', p.id, p.payload!);
      out.add(VaultEntry(item: VaultItem.fromJson(p.id, data), pending: p));
    }
    return out;
  }

  Future<void> save(VaultItem item) async {
    final data = item.toJson();
    final existing = await store.pendingFor(item.id);
    if (existing != null && existing.op == PendingOp.upsert) {
      await store.putPending(existing.copyWith(payload: codec.sealLocal('pending', item.id, data)));
      return;
    }
    final remote = await store.item(item.id);
    if (remote != null) {
      if (!remote.canWrite) throw StateError('read-only item');
      await store.putPending(PendingChange(
        id: item.id,
        op: PendingOp.upsert,
        payload: codec.sealLocal('pending', item.id, data),
        base: codec.sealLocal('base', item.id, codec.openRemote(remote)),
        baseRevision: remote.itemRevision,
      ));
      return;
    }
    final (key, wrapped) = codec.newItemKey(item.id);
    key.dispose();
    await store.putPending(PendingChange(
      id: item.id,
      op: PendingOp.upsert,
      payload: codec.sealLocal('pending', item.id, data),
      wrappedKey: wrapped,
    ));
  }

  Future<void> delete(String id) async {
    final remote = await store.item(id);
    final pending = await store.pendingFor(id);
    if (remote == null) {
      await store.removePending(id);
      return;
    }
    if (!remote.isOwner) throw StateError('only the owner can delete');
    await store.putPending(PendingChange(
      id: id,
      op: PendingOp.delete,
      baseRevision: pending?.baseRevision ?? remote.itemRevision,
    ));
  }

  Future<ConflictView?> conflict(String id) async {
    final pending = await store.pendingFor(id);
    final remote = await store.item(id);
    if (pending == null || !pending.inConflict || remote == null) return null;
    return ConflictView(
      codec.openLocal('pending', id, pending.payload!),
      codec.openRemote(remote),
      pending.conflictFields,
    );
  }

  Future<void> resolve(String id, Map<String, dynamic> chosen) async {
    final pending = await store.pendingFor(id);
    if (pending == null) return;
    await store.putPending(
        pending.copyWith(payload: codec.sealLocal('pending', id, chosen), conflictFields: const []));
  }

  /// Saves unsynced changes as a brand-new item owned by this user.
  Future<String> keepAsCopy(PendingChange pending) async {
    await store.removePending(pending.id);
    final data = codec.openLocal('pending', pending.id, pending.payload!);
    final id = newId();
    final (key, wrapped) = codec.newItemKey(id);
    key.dispose();
    await store.putPending(PendingChange(
      id: id,
      op: PendingOp.upsert,
      payload: codec.sealLocal('pending', id, data),
      wrappedKey: wrapped,
    ));
    return (data['title'] as String?)?.trim().isNotEmpty == true ? data['title'] as String : 'An item';
  }
}
