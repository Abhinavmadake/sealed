import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sealed_app/core/crypto/account_keys.dart';
import 'package:sealed_app/core/crypto/base32.dart';
import 'package:sealed_app/core/crypto/item_crypto.dart';
import 'package:sealed_app/core/crypto/sealed_crypto.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late SealedCrypto crypto;
  late AccountKeys accounts;
  late ItemCrypto items;

  setUpAll(() async {
    crypto = await SealedCrypto.init(kdfOps: minKdfOps, kdfMem: minKdfMem);
    accounts = AccountKeys(crypto);
    items = ItemCrypto(crypto);
  });

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  group('sealed blobs', () {
    test('round trip', () {
      final key = crypto.newKey();
      final blob = crypto.seal(key, bytes('hello'), 'label');
      expect(blob.length, 1 + nonceBytes + 5 + 16);
      expect(blob[0], blobVersion);
      expect(utf8.decode(crypto.open(key, blob, 'label')), 'hello');
    });

    test('same message encrypts differently each time', () {
      final key = crypto.newKey();
      expect(crypto.seal(key, bytes('x'), 'l'), isNot(crypto.seal(key, bytes('x'), 'l')));
    });

    test('wrong label, key, version or a flipped bit all fail', () {
      final key = crypto.newKey();
      final blob = crypto.seal(key, bytes('hello'), 'label');
      expect(() => crypto.open(key, blob, 'other'), throwsA(isA<DecryptionFailed>()));
      expect(() => crypto.open(crypto.newKey(), blob, 'label'), throwsA(isA<DecryptionFailed>()));
      final tampered = Uint8List.fromList(blob)..[blob.length - 1] ^= 1;
      expect(() => crypto.open(key, tampered, 'label'), throwsA(isA<DecryptionFailed>()));
      final versioned = Uint8List.fromList(blob)..[0] = 2;
      expect(() => crypto.open(key, versioned, 'label'), throwsA(isA<DecryptionFailed>()));
      expect(() => crypto.open(key, blob.sublist(0, 20), 'label'), throwsA(isA<DecryptionFailed>()));
    });

    test('wrapped keys have the size the server expects', () {
      expect(crypto.wrapKey(crypto.newKey(), crypto.newKey(), 'l').length, wrappedKeyBytes);
      final a = crypto.newKeyPair();
      final b = crypto.newKeyPair();
      expect(crypto.boxKey(crypto.newKey(), b.publicKey, a.secretKey).length, wrappedKeyBytes);
    });
  });

  group('password derivation', () {
    test('is deterministic for the same password and salt', () async {
      final kdf = crypto.newKdfParams();
      final a = await crypto.deriveFromPassword('correct horse', kdf);
      final b = await crypto.deriveFromPassword('correct horse', kdf);
      expect(a.authKey, b.authKey);
      expect(a.wrapKey.extractBytes(), b.wrapKey.extractBytes());
      expect(a.authKey, isNot(a.wrapKey.extractBytes()));
    });

    test('changes with the salt or the password', () async {
      final kdf = crypto.newKdfParams();
      final base = await crypto.deriveFromPassword('correct horse', kdf);
      final otherSalt = await crypto.deriveFromPassword('correct horse', crypto.newKdfParams());
      final otherPassword = await crypto.deriveFromPassword('correct horsf', kdf);
      expect(base.authKey, isNot(otherSalt.authKey));
      expect(base.authKey, isNot(otherPassword.authKey));
    });

    test('refuses parameters below the floor', () async {
      final salt = crypto.random(saltBytes);
      expect(() => crypto.deriveFromPassword('pw', KdfParams(salt: salt, ops: 1, mem: minKdfMem)),
          throwsA(isA<WeakKdfParams>()));
      expect(() => crypto.deriveFromPassword('pw', KdfParams(salt: salt, ops: 3, mem: 8 << 20)),
          throwsA(isA<WeakKdfParams>()));
    });
  });

  group('account', () {
    late RegistrationMaterial reg;

    setUpAll(() async => reg = await accounts.register('hunter2 is a bad password'));

    UnlockedAccount unlockWith(DerivedKeys keys, Uint8List wrappedAccountKey) => accounts.unlock(
          keys.wrapKey,
          wrappedAccountKey: wrappedAccountKey,
          publicKey: reg.account.publicKey,
          wrappedPrivateKey: reg.wrappedPrivateKey,
        );

    test('master password unlocks the account key and private key', () async {
      final keys = await accounts.derive('hunter2 is a bad password', reg.password.kdf);
      expect(keys.authKey, reg.password.authKey);
      final unlocked = unlockWith(keys, reg.password.wrappedAccountKey);
      expect(unlocked.accountKey.extractBytes(), reg.account.accountKey.extractBytes());
      expect(unlocked.keyPair.secretKey.extractBytes(), reg.account.keyPair.secretKey.extractBytes());
    });

    test('wrong password fails', () async {
      final keys = await accounts.derive('hunter3 is a bad password', reg.password.kdf);
      expect(keys.authKey, isNot(reg.password.authKey));
      expect(() => unlockWith(keys, reg.password.wrappedAccountKey), throwsA(isA<DecryptionFailed>()));
    });

    test('a swapped public key is detected', () async {
      final keys = await accounts.derive('hunter2 is a bad password', reg.password.kdf);
      expect(
        () => accounts.unlock(keys.wrapKey,
            wrappedAccountKey: reg.password.wrappedAccountKey,
            publicKey: crypto.newKeyPair().publicKey,
            wrappedPrivateKey: reg.wrappedPrivateKey),
        throwsA(isA<DecryptionFailed>()),
      );
    });

    test('changing the password keeps the same account key', () async {
      final changed = await accounts.rekey('a much better passphrase', reg.account.accountKey);
      final keys = await accounts.derive('a much better passphrase', changed.kdf);
      expect(keys.authKey, changed.authKey);
      final unlocked = unlockWith(keys, changed.wrappedAccountKey);
      expect(unlocked.accountKey.extractBytes(), reg.account.accountKey.extractBytes());
    });

    test('recovery key recovers the account key', () {
      expect(reg.recoveryKey, matches(RegExp(r'^([A-Z2-7]{4}-){12}[A-Z2-7]{4}$')));
      final messy = reg.recoveryKey.toLowerCase().replaceAll('-', ' ');
      final recovery = accounts.recoveryKeys(messy);
      expect(recovery.authKey, reg.recoveryAuth);
      final key = accounts.recoverAccountKey(recovery, reg.recoveryWrappedKey);
      expect(key.extractBytes(), reg.account.accountKey.extractBytes());
    });

    test('a mistyped recovery key fails', () {
      final chars = reg.recoveryKey.split('');
      chars[0] = chars[0] == 'A' ? 'B' : 'A';
      final recovery = accounts.recoveryKeys(chars.join());
      expect(recovery.authKey, isNot(reg.recoveryAuth));
      expect(() => accounts.recoverAccountKey(recovery, reg.recoveryWrappedKey),
          throwsA(isA<DecryptionFailed>()));
      expect(() => accounts.recoveryKeys('too-short'), throwsFormatException);
    });
  });

  group('items', () {
    late UnlockedAccount alice;
    late UnlockedAccount bob;

    setUpAll(() async {
      alice = (await accounts.register('alice password')).account;
      bob = (await accounts.register('bob password')).account;
    });

    const id = '0b8a4a6e-1f7c-4d1e-9b77-3c3f1c9a8d10';
    final data = {'title': 'Email', 'username': 'alice', 'password': 'p4ss'};

    test('round trip and length is padded', () {
      final key = items.newItemKey();
      final short = items.encrypt(key, id, {'t': 'a'});
      final longer = items.encrypt(key, id, {'t': 'a' * 100});
      expect(short.length, longer.length);
      expect(items.decrypt(key, id, items.encrypt(key, id, data)), data);
    });

    test('ciphertext moved to another item id fails', () {
      final key = items.newItemKey();
      final blob = items.encrypt(key, id, data);
      expect(() => items.decrypt(key, '11111111-1f7c-4d1e-9b77-3c3f1c9a8d10', blob),
          throwsA(isA<DecryptionFailed>()));
    });

    test('owner unwraps own item key', () {
      final key = items.newItemKey();
      final wrapped = items.wrapForSelf(alice, key, id);
      final back = items.unwrap(account: alice, itemId: id, kind: KeyKind.self, wrappedKey: wrapped);
      expect(back.extractBytes(), key.extractBytes());
      expect(() => items.unwrap(account: bob, itemId: id, kind: KeyKind.self, wrappedKey: wrapped),
          throwsA(isA<DecryptionFailed>()));
    });

    test('shared key opens only for the recipient and only from the real sender', () async {
      final mallory = (await accounts.register('mallory password')).account;
      final key = items.newItemKey();
      final boxed = items.wrapForRecipient(alice, key, bob.publicKey);
      final back = items.unwrap(
          account: bob, itemId: id, kind: KeyKind.box, wrappedKey: boxed, senderPublicKey: alice.publicKey);
      expect(back.extractBytes(), key.extractBytes());
      expect(
          () => items.unwrap(
              account: bob, itemId: id, kind: KeyKind.box, wrappedKey: boxed, senderPublicKey: mallory.publicKey),
          throwsA(isA<DecryptionFailed>()));
      expect(
          () => items.unwrap(
              account: mallory, itemId: id, kind: KeyKind.box, wrappedKey: boxed, senderPublicKey: alice.publicKey),
          throwsA(isA<DecryptionFailed>()));
      final forged = items.wrapForRecipient(mallory, items.newItemKey(), bob.publicKey);
      expect(
          () => items.unwrap(
              account: bob, itemId: id, kind: KeyKind.box, wrappedKey: forged, senderPublicKey: alice.publicKey),
          throwsA(isA<DecryptionFailed>()));
    });

    test('fingerprints are stable, readable and distinct', () {
      final f = crypto.fingerprint(alice.publicKey);
      expect(f, matches(RegExp(r'^(\d{5} ){5}\d{5}$')));
      expect(crypto.fingerprint(alice.publicKey), f);
      expect(crypto.fingerprint(bob.publicKey), isNot(f));
    });
  });

  group('base32', () {
    test('round trips random data', () {
      for (var i = 0; i < 50; i++) {
        final data = crypto.random(32);
        expect(base32Decode(base32Encode(data), 32), data);
      }
    });

    test('rejects bad input', () {
      final good = base32Encode(crypto.random(32));
      expect(() => base32Decode('${good}A', 32), throwsFormatException);
      expect(() => base32Decode('${good.substring(1)}1', 32), throwsFormatException);
      final last = good.substring(0, good.length - 1);
      expect(() => base32Decode('${last}7', 32), throwsFormatException);
    });
  });
}
