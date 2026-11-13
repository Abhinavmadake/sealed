import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'base32.dart';
import 'labels.dart';
import 'sealed_crypto.dart';

class UnlockedAccount {
  UnlockedAccount(this.accountKey, this.keyPair);

  final SecureKey accountKey;
  final KeyPair keyPair;

  Uint8List get publicKey => keyPair.publicKey;

  void dispose() {
    accountKey.dispose();
    keyPair.secretKey.dispose();
  }
}

class PasswordMaterial {
  PasswordMaterial(this.kdf, this.authKey, this.wrappedAccountKey);

  final KdfParams kdf;
  final Uint8List authKey;
  final Uint8List wrappedAccountKey;
}

class RegistrationMaterial {
  RegistrationMaterial({
    required this.password,
    required this.wrappedPrivateKey,
    required this.recoveryAuth,
    required this.recoveryWrappedKey,
    required this.recoveryKey,
    required this.account,
  });

  final PasswordMaterial password;
  final Uint8List wrappedPrivateKey;
  final Uint8List recoveryAuth;
  final Uint8List recoveryWrappedKey;
  final String recoveryKey;
  final UnlockedAccount account;
}

class AccountKeys {
  AccountKeys(this.crypto);

  final SealedCrypto crypto;

  Future<RegistrationMaterial> register(String masterPassword) async {
    final accountKey = crypto.newKey();
    final keyPair = crypto.newKeyPair();
    final password = await rekey(masterPassword, accountKey);

    final recoveryBytes = crypto.random(keyBytes);
    final recovery = crypto.splitKey(crypto.keyFromBytes(recoveryBytes));
    final recoveryWrappedKey = crypto.wrapKey(recovery.wrapKey, accountKey, Labels.recovery);
    recovery.wrapKey.dispose();

    return RegistrationMaterial(
      password: password,
      wrappedPrivateKey: crypto.wrapKey(accountKey, keyPair.secretKey, Labels.privateKey),
      recoveryAuth: recovery.authKey,
      recoveryWrappedKey: recoveryWrappedKey,
      recoveryKey: formatRecoveryKey(recoveryBytes),
      account: UnlockedAccount(accountKey, keyPair),
    );
  }

  Future<PasswordMaterial> rekey(String masterPassword, SecureKey accountKey) async {
    final kdf = crypto.newKdfParams();
    final derived = await crypto.deriveFromPassword(masterPassword, kdf);
    final wrapped = crypto.wrapKey(derived.wrapKey, accountKey, Labels.accountKey);
    derived.wrapKey.dispose();
    return PasswordMaterial(kdf, derived.authKey, wrapped);
  }

  Future<DerivedKeys> derive(String masterPassword, KdfParams kdf) =>
      crypto.deriveFromPassword(masterPassword, kdf);

  UnlockedAccount unlock(
    SecureKey wrapKey, {
    required Uint8List wrappedAccountKey,
    required Uint8List publicKey,
    required Uint8List wrappedPrivateKey,
  }) {
    final accountKey = crypto.unwrapKey(wrapKey, wrappedAccountKey, Labels.accountKey);
    try {
      return unlockWithAccountKey(accountKey,
          publicKey: publicKey, wrappedPrivateKey: wrappedPrivateKey);
    } catch (_) {
      accountKey.dispose();
      rethrow;
    }
  }

  UnlockedAccount unlockWithAccountKey(
    SecureKey accountKey, {
    required Uint8List publicKey,
    required Uint8List wrappedPrivateKey,
  }) {
    final secretKey = crypto.unwrapKey(accountKey, wrappedPrivateKey, Labels.privateKey);
    if (!_equal(crypto.publicKeyOf(secretKey), publicKey)) {
      secretKey.dispose();
      throw const DecryptionFailed('public key does not match the private key');
    }
    return UnlockedAccount(accountKey, KeyPair(publicKey: publicKey, secretKey: secretKey));
  }

  DerivedKeys recoveryKeys(String recoveryKey) {
    final Uint8List bytes;
    try {
      bytes = base32Decode(recoveryKey, keyBytes);
    } on FormatException {
      throw const FormatException('That does not look like a recovery key');
    }
    return crypto.splitKey(crypto.keyFromBytes(bytes));
  }

  SecureKey recoverAccountKey(DerivedKeys recovery, Uint8List recoveryWrappedKey) =>
      crypto.unwrapKey(recovery.wrapKey, recoveryWrappedKey, Labels.recovery);

  static String formatRecoveryKey(Uint8List bytes) => groupEvery(base32Encode(bytes), 4);
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
