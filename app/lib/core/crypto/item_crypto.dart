import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'account_keys.dart';
import 'labels.dart';
import 'sealed_crypto.dart';

enum KeyKind { self, box }

class ItemCrypto {
  ItemCrypto(this.crypto);

  static const padBlock = 256;

  final SealedCrypto crypto;

  SecureKey newItemKey() => crypto.newKey();

  Uint8List encrypt(SecureKey itemKey, String itemId, Map<String, dynamic> data) {
    final padded = crypto.pad(Uint8List.fromList(utf8.encode(jsonEncode(data))), padBlock);
    return crypto.seal(itemKey, padded, Labels.item(itemId));
  }

  Map<String, dynamic> decrypt(SecureKey itemKey, String itemId, Uint8List blob) {
    final padded = crypto.open(itemKey, blob, Labels.item(itemId));
    final decoded = jsonDecode(utf8.decode(crypto.unpad(padded, padBlock)));
    if (decoded is! Map<String, dynamic>) throw const DecryptionFailed('item is not an object');
    return decoded;
  }

  Uint8List wrapForSelf(UnlockedAccount account, SecureKey itemKey, String itemId) =>
      crypto.wrapKey(account.accountKey, itemKey, Labels.itemKey(itemId));

  Uint8List wrapForRecipient(UnlockedAccount sender, SecureKey itemKey, Uint8List recipientPublicKey) =>
      crypto.boxKey(itemKey, recipientPublicKey, sender.keyPair.secretKey);

  SecureKey unwrap({
    required UnlockedAccount account,
    required String itemId,
    required KeyKind kind,
    required Uint8List wrappedKey,
    Uint8List? senderPublicKey,
  }) {
    switch (kind) {
      case KeyKind.self:
        return crypto.unwrapKey(account.accountKey, wrappedKey, Labels.itemKey(itemId));
      case KeyKind.box:
        if (senderPublicKey == null) throw const DecryptionFailed('missing sender key');
        return crypto.unboxKey(wrappedKey, senderPublicKey, account.keyPair.secretKey);
    }
  }
}
