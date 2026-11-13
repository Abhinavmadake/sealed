import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../api/dto.dart';
import '../crypto/account_keys.dart';
import '../crypto/item_crypto.dart';
import '../crypto/sealed_crypto.dart';

/// Applies the unlocked keys: item keys for server data, the account key for local-only data.
class VaultCodec {
  VaultCodec(this.crypto, this.account) : items = ItemCrypto(crypto);

  final SealedCrypto crypto;
  final ItemCrypto items;
  final UnlockedAccount account;

  SecureKey keyFor(RemoteItem remote) {
    final kind = remote.keyKind;
    final wrapped = remote.wrappedKey;
    if (kind == null || wrapped == null) throw const DecryptionFailed('item has no key');
    return items.unwrap(
      account: account,
      itemId: remote.id,
      kind: kind,
      wrappedKey: wrapped,
      senderPublicKey: remote.grantedByPublicKey,
    );
  }

  Map<String, dynamic> openRemote(RemoteItem remote) {
    final blob = remote.blob;
    if (blob == null) throw const DecryptionFailed('item has no content');
    final key = keyFor(remote);
    try {
      return items.decrypt(key, remote.id, blob);
    } finally {
      key.dispose();
    }
  }

  Uint8List sealFor(SecureKey key, String id, Map<String, dynamic> data) => items.encrypt(key, id, data);

  (SecureKey, Uint8List) newItemKey(String id) {
    final key = items.newItemKey();
    return (key, items.wrapForSelf(account, key, id));
  }

  SecureKey unwrapOwn(String id, Uint8List wrapped) =>
      items.unwrap(account: account, itemId: id, kind: KeyKind.self, wrappedKey: wrapped);

  Uint8List sealLocal(String kind, String id, Map<String, dynamic> data) => crypto.seal(
        account.accountKey,
        crypto.pad(Uint8List.fromList(utf8.encode(jsonEncode(data))), ItemCrypto.padBlock),
        'sealed.local.v1:$kind:$id',
      );

  Map<String, dynamic> openLocal(String kind, String id, Uint8List blob) {
    final padded = crypto.open(account.accountKey, blob, 'sealed.local.v1:$kind:$id');
    return jsonDecode(utf8.decode(crypto.unpad(padded, ItemCrypto.padBlock))) as Map<String, dynamic>;
  }

  Uint8List sealSecret(String name, String value) =>
      crypto.seal(account.accountKey, Uint8List.fromList(utf8.encode(value)), 'sealed.local.v1:secret:$name');

  String openSecret(String name, Uint8List blob) =>
      utf8.decode(crypto.open(account.accountKey, blob, 'sealed.local.v1:secret:$name'));
}
