import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

const blobVersion = 1;
const keyBytes = 32;
const saltBytes = 16;
const nonceBytes = 24;
const wrappedKeyBytes = 1 + nonceBytes + keyBytes + 16;

const minKdfOps = 3;
const minKdfMem = 64 * 1024 * 1024;

const _kdfContext = 'sealedv1';
final _authKeyId = BigInt.one;
final _wrapKeyId = BigInt.two;

class DecryptionFailed implements Exception {
  const DecryptionFailed([this.reason = 'decryption failed']);
  final String reason;
  @override
  String toString() => reason;
}

class WeakKdfParams implements Exception {
  @override
  String toString() => 'key derivation parameters are below the minimum';
}

class KdfParams {
  const KdfParams({required this.salt, required this.ops, required this.mem});
  final Uint8List salt;
  final int ops;
  final int mem;
}

class DerivedKeys {
  DerivedKeys(this.authKey, this.wrapKey);
  final Uint8List authKey;
  final SecureKey wrapKey;
}

class SealedCrypto {
  SealedCrypto(this.sodium, {int? kdfOps, int? kdfMem})
      : kdfOps = kdfOps ?? sodium.crypto.pwhash.opsLimitModerate,
        kdfMem = kdfMem ?? sodium.crypto.pwhash.memLimitModerate;

  final SodiumSumo sodium;
  final int kdfOps;
  final int kdfMem;

  static Future<SealedCrypto> init({int? kdfOps, int? kdfMem}) async =>
      SealedCrypto(await SodiumSumoInit.init(), kdfOps: kdfOps, kdfMem: kdfMem);

  Aead get _aead => sodium.crypto.aeadXChaCha20Poly1305IETF;

  Uint8List random(int length) => sodium.randombytes.buf(length);

  SecureKey newKey() => _aead.keygen();

  SecureKey keyFromBytes(Uint8List bytes) => SecureKey.fromList(sodium, bytes);

  KdfParams newKdfParams() => KdfParams(salt: random(saltBytes), ops: kdfOps, mem: kdfMem);

  Future<DerivedKeys> deriveFromPassword(String password, KdfParams params) async {
    if (params.ops < minKdfOps || params.mem < minKdfMem) throw WeakKdfParams();
    if (params.salt.length != saltBytes) throw const FormatException('bad salt');
    final pwhash = sodium.crypto.pwhash;
    final passwordBytes = Int8List.fromList(utf8.encode(password));
    final master = await sodium.runIsolated(
      (_, _) => pwhash(
        outLen: keyBytes,
        password: passwordBytes,
        salt: params.salt,
        opsLimit: params.ops,
        memLimit: params.mem,
        alg: CryptoPwhashAlgorithm.argon2id13,
      ),
    );
    return splitKey(master);
  }

  DerivedKeys splitKey(SecureKey master) {
    final kdf = sodium.crypto.kdf;
    final auth = kdf.deriveFromKey(
        masterKey: master, context: _kdfContext, subkeyId: _authKeyId, subkeyLen: keyBytes);
    final wrap = kdf.deriveFromKey(
        masterKey: master, context: _kdfContext, subkeyId: _wrapKeyId, subkeyLen: keyBytes);
    final authBytes = auth.extractBytes();
    auth.dispose();
    master.dispose();
    return DerivedKeys(authBytes, wrap);
  }

  Uint8List seal(SecureKey key, Uint8List message, String label) {
    final nonce = random(nonceBytes);
    final cipher = _aead.encrypt(
        message: message, nonce: nonce, key: key, additionalData: utf8.encode(label));
    return Uint8List.fromList([blobVersion, ...nonce, ...cipher]);
  }

  Uint8List open(SecureKey key, Uint8List blob, String label) {
    _checkHeader(blob);
    try {
      return _aead.decrypt(
        cipherText: blob.sublist(1 + nonceBytes),
        nonce: blob.sublist(1, 1 + nonceBytes),
        key: key,
        additionalData: utf8.encode(label),
      );
    } on SodiumException {
      throw const DecryptionFailed();
    }
  }

  Uint8List wrapKey(SecureKey wrapping, SecureKey key, String label) =>
      seal(wrapping, key.extractBytes(), label);

  SecureKey unwrapKey(SecureKey wrapping, Uint8List blob, String label) {
    final bytes = open(wrapping, blob, label);
    if (bytes.length != keyBytes) throw const DecryptionFailed('wrapped key has the wrong size');
    return keyFromBytes(bytes);
  }

  KeyPair newKeyPair() => sodium.crypto.box.keyPair();

  Uint8List publicKeyOf(SecureKey secretKey) =>
      sodium.crypto.scalarmult.base(n: secretKey);

  Uint8List boxKey(SecureKey key, Uint8List recipientPublicKey, SecureKey senderSecretKey) {
    final nonce = random(nonceBytes);
    final cipher = sodium.crypto.box.easy(
      message: key.extractBytes(),
      nonce: nonce,
      publicKey: recipientPublicKey,
      secretKey: senderSecretKey,
    );
    return Uint8List.fromList([blobVersion, ...nonce, ...cipher]);
  }

  SecureKey unboxKey(Uint8List blob, Uint8List senderPublicKey, SecureKey recipientSecretKey) {
    _checkHeader(blob);
    try {
      final bytes = sodium.crypto.box.openEasy(
        cipherText: blob.sublist(1 + nonceBytes),
        nonce: blob.sublist(1, 1 + nonceBytes),
        publicKey: senderPublicKey,
        secretKey: recipientSecretKey,
      );
      if (bytes.length != keyBytes) throw const DecryptionFailed('shared key has the wrong size');
      return keyFromBytes(bytes);
    } on SodiumException {
      throw const DecryptionFailed('shared key did not come from the expected sender');
    }
  }

  Uint8List pad(Uint8List data, int block) => sodium.pad(data, block);

  Uint8List unpad(Uint8List data, int block) {
    try {
      return sodium.unpad(data, block);
    } on SodiumException {
      throw const DecryptionFailed('bad padding');
    }
  }

  String fingerprint(Uint8List publicKey) {
    final hash = sodium.crypto.genericHash(
        message: Uint8List.fromList([...utf8.encode('sealed.fingerprint.v1'), ...publicKey]),
        outLen: 30);
    final groups = <String>[];
    for (var i = 0; i < 30; i += 5) {
      var value = 0;
      for (var j = 0; j < 5; j++) {
        value = value * 256 + hash[i + j];
      }
      groups.add((value % 100000).toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }

  void _checkHeader(Uint8List blob) {
    if (blob.length < 1 + nonceBytes + 16) throw const DecryptionFailed('ciphertext too short');
    if (blob[0] != blobVersion) throw const DecryptionFailed('unknown ciphertext version');
  }
}
