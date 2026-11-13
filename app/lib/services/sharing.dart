import 'dart:typed_data';

import '../core/api/api_client.dart';
import '../core/api/dto.dart';
import '../core/sync/vault_repository.dart';

class KeyChanged implements Exception {
  KeyChanged(this.email);

  final String email;

  @override
  String toString() => "$email's security key has changed since you last shared with them";
}

class Sharing {
  Sharing(this.api, this.repo, this.userId);

  final ApiClient api;
  final VaultRepository repo;
  final String userId;

  Future<UserInfo?> findUser(String email) => api.lookup(email);

  Future<bool> isPinned(UserInfo user) async => await repo.store.pinnedKey(user.id) != null;

  Future<void> share(String itemId, UserInfo user, String permission) async {
    await _checkPin(user);
    final remote = await _ownedSynced(itemId);
    final key = repo.codec.keyFor(remote);
    final wrapped = repo.codec.items.wrapForRecipient(repo.codec.account, key, user.publicKey);
    key.dispose();
    await api.addGrant(itemId, user.id, wrapped, permission);
    await repo.store.pinKey(user.id, user.email, user.publicKey);
  }

  Future<List<GrantInfo>> grants(String itemId) => api.grants(itemId);

  /// Removes a user and rotates the item key, re-wrapping it for everyone who keeps access.
  Future<void> revoke(String itemId, String revokedUserId) async {
    final remote = await _ownedSynced(itemId);
    final data = repo.codec.openRemote(remote);
    final keep = (await api.grants(itemId)).where((g) => g.user.id != revokedUserId).toList();
    for (final g in keep) {
      if (g.user.id != userId) await _checkPin(g.user);
    }
    final codec = repo.codec;
    final newKey = codec.items.newItemKey();
    final rewrapped = <String, Uint8List>{
      for (final g in keep)
        g.user.id: g.user.id == userId
            ? codec.items.wrapForSelf(codec.account, newKey, itemId)
            : codec.items.wrapForRecipient(codec.account, newKey, g.user.publicKey),
    };
    final blob = codec.sealFor(newKey, itemId, data);
    newKey.dispose();
    final result = await api.revoke(
      itemId,
      userId: revokedUserId,
      baseRevision: remote.itemRevision,
      blob: blob,
      rewrapped: rewrapped,
    );
    await repo.store.putItem(result);
  }

  Future<RemoteItem> _ownedSynced(String itemId) async {
    if (await repo.store.pendingFor(itemId) != null) {
      throw StateError('Sync this item before changing who it is shared with');
    }
    final remote = await repo.store.item(itemId);
    if (remote == null || !remote.isOwner) throw StateError('Only the owner can change sharing');
    return remote;
  }

  Future<void> _checkPin(UserInfo user) async {
    final pinned = await repo.store.pinnedKey(user.id);
    if (pinned != null && !_equal(pinned, user.publicKey)) throw KeyChanged(user.email);
  }
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
