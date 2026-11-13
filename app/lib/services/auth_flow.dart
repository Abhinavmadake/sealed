import '../core/api/api_client.dart';
import '../core/api/dto.dart';
import '../core/crypto/account_keys.dart';
import '../core/crypto/sealed_crypto.dart';
import '../core/store/local_store.dart';
import '../core/sync/vault_codec.dart';

class WrongPassword implements Exception {
  @override
  String toString() => 'Wrong master password';
}

class AuthFlow {
  AuthFlow(this.crypto, this.store) : keys = AccountKeys(crypto);

  final SealedCrypto crypto;
  final LocalStore store;
  final AccountKeys keys;

  Future<(UnlockedAccount, String)> register(
      ApiClient api, String email, String password, String deviceName) async {
    final material = await keys.register(password);
    final response = await api.register(email, material, deviceName);
    await store.clearAll();
    await _save(api, response, deviceName, material.account);
    return (material.account, material.recoveryKey);
  }

  Future<UnlockedAccount> login(ApiClient api, String email, String password, String deviceName) async {
    final kdf = await api.prelogin(email);
    final derived = await keys.derive(password, kdf);
    final response = await api.login(email, derived.authKey, deviceName);
    final account = keys.unlock(
      derived.wrapKey,
      wrappedAccountKey: response.wrappedAccountKey,
      publicKey: response.publicKey,
      wrappedPrivateKey: response.wrappedPrivateKey,
    );
    derived.wrapKey.dispose();
    final existing = await store.account();
    if (existing != null && existing.userId != response.userId) await store.clearAll();
    await _save(api, response, deviceName, account);
    return account;
  }

  /// Works offline: the wrapped keys are cached on the device.
  Future<UnlockedAccount> unlock(String password) async {
    final record = await store.account();
    if (record == null) throw StateError('no account on this device');
    final derived = await keys.derive(password, record.kdf);
    try {
      return keys.unlock(
        derived.wrapKey,
        wrappedAccountKey: record.wrappedAccountKey,
        publicKey: record.publicKey,
        wrappedPrivateKey: record.wrappedPrivateKey,
      );
    } on DecryptionFailed {
      throw WrongPassword();
    } finally {
      derived.wrapKey.dispose();
    }
  }

  Future<String?> token(UnlockedAccount account) async {
    final sealed = (await store.account())?.sealedToken;
    if (sealed == null) return null;
    return VaultCodec(crypto, account).openSecret('token', sealed);
  }

  Future<void> changePassword(
      ApiClient api, UnlockedAccount account, String currentPassword, String newPassword) async {
    final record = (await store.account())!;
    final current = await keys.derive(currentPassword, record.kdf);
    current.wrapKey.dispose();
    final material = await keys.rekey(newPassword, account.accountKey);
    try {
      await api.changePassword(current.authKey, material);
    } on ApiException catch (e) {
      if (e.status == 401) throw WrongPassword();
      rethrow;
    }
    await store.saveAccount(AccountRecord(
      serverUrl: record.serverUrl,
      email: record.email,
      userId: record.userId,
      deviceName: record.deviceName,
      kdf: material.kdf,
      wrappedAccountKey: material.wrappedAccountKey,
      publicKey: record.publicKey,
      wrappedPrivateKey: record.wrappedPrivateKey,
      sessionId: record.sessionId,
      sealedToken: record.sealedToken,
    ));
  }

  Future<UnlockedAccount> recover(
      ApiClient api, String email, String recoveryKey, String newPassword, String deviceName) async {
    final recovery = keys.recoveryKeys(recoveryKey);
    final wrapped = await api.recoverStart(email, recovery.authKey);
    final accountKey = keys.recoverAccountKey(recovery, wrapped);
    recovery.wrapKey.dispose();
    final material = await keys.rekey(newPassword, accountKey);
    final response = await api.recoverFinish(email, recovery.authKey, material, deviceName);
    final account = keys.unlockWithAccountKey(
      accountKey,
      publicKey: response.publicKey,
      wrappedPrivateKey: response.wrappedPrivateKey,
    );
    final existing = await store.account();
    if (existing != null && existing.userId != response.userId) await store.clearAll();
    await _save(api, response, deviceName, account);
    return account;
  }

  Future<void> _save(ApiClient api, LoginResponse r, String deviceName, UnlockedAccount account) async {
    await store.saveAccount(AccountRecord(
      serverUrl: api.baseUrl,
      email: r.email,
      userId: r.userId,
      deviceName: deviceName,
      kdf: r.kdf,
      wrappedAccountKey: r.wrappedAccountKey,
      publicKey: r.publicKey,
      wrappedPrivateKey: r.wrappedPrivateKey,
      sessionId: r.sessionId,
      sealedToken: VaultCodec(crypto, account).sealSecret('token', r.token),
    ));
    api.token = r.token;
  }
}
