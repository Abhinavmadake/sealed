import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sealed_app/core/api/api_client.dart';
import 'package:sealed_app/core/crypto/account_keys.dart';
import 'package:sealed_app/core/crypto/sealed_crypto.dart';
import 'package:sealed_app/core/store/local_store.dart';
import 'package:sealed_app/core/sync/sync_engine.dart';
import 'package:sealed_app/core/sync/vault_codec.dart';
import 'package:sealed_app/core/sync/vault_repository.dart';
import 'package:sealed_app/models/vault_item.dart';
import 'package:sealed_app/services/auth_flow.dart';
import 'package:sealed_app/services/sharing.dart';
import 'package:sembast/sembast_memory.dart';

const server = String.fromEnvironment('SEALED_SERVER', defaultValue: 'http://10.0.2.2:8000');
late SealedCrypto crypto;
var _dbCount = 0;
final _run = DateTime.now().millisecondsSinceEpoch;

String email(String name) => '$name-$_run@example.com';

class Device {
  Device(this.api, this.store, this.account, this.userId)
      : repo = VaultRepository(store, VaultCodec(crypto, account)) {
    engine = SyncEngine(api, repo);
    sharing = Sharing(api, repo, userId);
  }

  final ApiClient api;
  final LocalStore store;
  final UnlockedAccount account;
  final String userId;
  final VaultRepository repo;
  late final SyncEngine engine;
  late final Sharing sharing;
  String recoveryKey = '';

  static Future<LocalStore> _store() async =>
      LocalStore(await newDatabaseFactoryMemory().openDatabase('device${_dbCount++}'));

  static Future<Device> signUp(String address, [String password = 'phone password']) async {
    final api = ApiClient(server);
    final store = await _store();
    final (account, recovery) = await AuthFlow(crypto, store).register(api, address, password, 'phone');
    return Device(api, store, account, (await store.account())!.userId)..recoveryKey = recovery;
  }

  static Future<Device> signIn(String address, [String password = 'phone password']) async {
    final api = ApiClient(server);
    final store = await _store();
    final account = await AuthFlow(crypto, store).login(api, address, password, 'laptop');
    return Device(api, store, account, (await store.account())!.userId);
  }

  Future<SyncReport> sync() => engine.sync();

  Future<VaultEntry?> entry(String id) async {
    for (final e in await repo.entries()) {
      if (e.item.id == id) return e;
    }
    return null;
  }

  Future<VaultItem> item(String id) async => (await entry(id))!.item;

  Future<String> add(String title, {String password = 'secret'}) async {
    final id = repo.newId();
    await repo.save(VaultItem(id: id, title: title, username: 'me', password: password, modifiedAt: DateTime.now()));
    return id;
  }

  Future<void> edit(String id, VaultItem Function(VaultItem) change) async =>
      repo.save(change(await item(id)).copyWith(modifiedAt: DateTime.now()));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    crypto = await SealedCrypto.init(kdfOps: minKdfOps, kdfMem: minKdfMem);
    expect(await ApiClient(server).health(), isTrue, reason: 'start the server with server/run_dev.sh');
  });

  test('an item created on one device appears on another', () async {
    final phone = await Device.signUp(email('a1'));
    final id = await phone.add('Email');
    expect((await phone.entry(id))!.synced, isFalse);
    final report = await phone.sync();
    expect(report.pushed, 1);
    expect((await phone.entry(id))!.synced, isTrue);

    final laptop = await Device.signIn(email('a1'));
    await laptop.sync();
    expect((await laptop.item(id)).title, 'Email');
  });

  test('the server only ever sees ciphertext', () async {
    final phone = await Device.signUp(email('a2'));
    await phone.add('Bank', password: 'correct-horse-battery-staple');
    await phone.sync();
    final (_, items) = await phone.api.sync(0);
    for (final i in items) {
      final raw = latin1.decode(i.blob!);
      expect(raw.contains('correct-horse'), isFalse);
      expect(raw.contains('Bank'), isFalse);
    }
  });

  test('offline edits to different fields merge automatically', () async {
    final phone = await Device.signUp(email('a3'));
    final id = await phone.add('Router');
    await phone.sync();
    final laptop = await Device.signIn(email('a3'));
    await laptop.sync();

    await phone.edit(id, (i) => i.copyWith(password: 'from-phone'));
    await laptop.edit(id, (i) => i.copyWith(notes: 'from-laptop'));
    await phone.sync();
    final report = await laptop.sync();
    expect(report.conflicts, isEmpty);
    await phone.sync();

    for (final d in [phone, laptop]) {
      final item = await d.item(id);
      expect(item.password, 'from-phone');
      expect(item.notes, 'from-laptop');
      expect((await d.entry(id))!.synced, isTrue);
    }
  });

  test('editing the same field on two devices asks the user', () async {
    final phone = await Device.signUp(email('a4'));
    final id = await phone.add('Wi-Fi');
    await phone.sync();
    final laptop = await Device.signIn(email('a4'));
    await laptop.sync();

    await phone.edit(id, (i) => i.copyWith(password: 'phone-pass', title: 'Home Wi-Fi'));
    await laptop.edit(id, (i) => i.copyWith(password: 'laptop-pass'));
    await phone.sync();
    final report = await laptop.sync();
    expect(report.conflicts, {id});
    expect((await laptop.entry(id))!.inConflict, isTrue);

    final conflict = (await laptop.repo.conflict(id))!;
    expect(conflict.fields, ['password']);
    expect(conflict.mine['password'], 'laptop-pass');
    expect(conflict.theirs['password'], 'phone-pass');
    expect(conflict.mine['title'], 'Home Wi-Fi');

    await laptop.repo.resolve(id, {...conflict.mine, 'password': 'phone-pass'});
    expect((await laptop.sync()).pushed, 1);
    await phone.sync();
    for (final d in [phone, laptop]) {
      final item = await d.item(id);
      expect(item.password, 'phone-pass');
      expect(item.title, 'Home Wi-Fi');
    }
  });

  test('editing an item deleted elsewhere keeps the edits as a new item', () async {
    final phone = await Device.signUp(email('a5'));
    final id = await phone.add('Old forum');
    await phone.sync();
    final laptop = await Device.signIn(email('a5'));
    await laptop.sync();

    await phone.repo.delete(id);
    await phone.sync();
    await laptop.edit(id, (i) => i.copyWith(password: 'still-needed'));
    final report = await laptop.sync();
    expect(report.notices.single, contains('kept as a new item'));
    expect(await laptop.entry(id), isNull);
    final copies = await laptop.repo.entries();
    expect(copies.single.item.password, 'still-needed');
    await laptop.sync();
    await phone.sync();
    expect((await phone.repo.entries()).single.item.password, 'still-needed');
  });

  test('a stale delete does not remove newer changes', () async {
    final phone = await Device.signUp(email('a6'));
    final id = await phone.add('Shared drive');
    await phone.sync();
    final laptop = await Device.signIn(email('a6'));
    await laptop.sync();

    await laptop.edit(id, (i) => i.copyWith(password: 'rotated'));
    await laptop.sync();
    await phone.repo.delete(id);
    final report = await phone.engine.sync();
    expect(await phone.entry(id), isNotNull);
    expect((await phone.item(id)).password, 'rotated');
    expect(report.notices.single, contains('not deleted'));
  });

  test('read-only sharing', () async {
    final alice = await Device.signUp(email('alice7'));
    final bob = await Device.signUp(email('bob7'));
    final id = await alice.add('Netflix', password: 'family-plan');
    await alice.sync();

    final found = (await alice.sharing.findUser(email('bob7')))!;
    expect(crypto.fingerprint(found.publicKey), crypto.fingerprint(bob.account.publicKey));
    await alice.sharing.share(id, found, 'read');
    await bob.sync();
    final entry = (await bob.entry(id))!;
    expect(entry.item.password, 'family-plan');
    expect(entry.sharedBy, email('alice7'));
    expect(entry.canWrite, isFalse);
    expect(() => bob.repo.save(entry.item.copyWith(password: 'x')), throwsStateError);
    expect(() => bob.repo.delete(id), throwsStateError);
  });

  test('write sharing lets the recipient edit', () async {
    final alice = await Device.signUp(email('alice8'));
    final bob = await Device.signUp(email('bob8'));
    final id = await alice.add('Team wiki');
    await alice.sync();
    await alice.sharing.share(id, (await alice.sharing.findUser(email('bob8')))!, 'write');
    await bob.sync();
    await bob.edit(id, (i) => i.copyWith(password: 'bob-changed-it'));
    expect((await bob.sync()).pushed, 1);
    await alice.sync();
    expect((await alice.item(id)).password, 'bob-changed-it');
  });

  test('revoking rotates the key and keeps the others working', () async {
    final alice = await Device.signUp(email('alice9'));
    final bob = await Device.signUp(email('bob9'));
    final carol = await Device.signUp(email('carol9'));
    final id = await alice.add('Office alarm', password: '4321');
    await alice.sync();
    await alice.sharing.share(id, (await alice.sharing.findUser(email('bob9')))!, 'read');
    await alice.sharing.share(id, (await alice.sharing.findUser(email('carol9')))!, 'read');
    await bob.sync();
    await carol.sync();
    final oldKey = (await bob.store.item(id))!.wrappedKey;

    await alice.sharing.revoke(id, bob.userId);
    await bob.sync();
    await carol.sync();
    await alice.sync();
    expect(await bob.entry(id), isNull);
    expect((await carol.item(id)).password, '4321');
    expect((await carol.store.item(id))!.wrappedKey, isNot(oldKey));
    expect((await alice.item(id)).password, '4321');
    final grants = await alice.sharing.grants(id);
    expect(grants.map((g) => g.user.email), containsAll([email('alice9'), email('carol9')]));
    expect(grants.map((g) => g.user.email), isNot(contains(email('bob9'))));
  });

  test('a changed public key is refused', () async {
    final alice = await Device.signUp(email('alice10'));
    final bob = await Device.signUp(email('bob10'));
    final id = await alice.add('Server');
    await alice.sync();
    final real = (await alice.sharing.findUser(email('bob10')))!;
    await alice.store.pinKey(bob.userId, real.email, crypto.newKeyPair().publicKey);
    expect(() => alice.sharing.share(id, real, 'read'), throwsA(isA<KeyChanged>()));
  });

  test('changing the password signs out other devices and keeps the vault', () async {
    final phone = await Device.signUp(email('a11'), 'first password');
    final id = await phone.add('Locker', password: '1234');
    await phone.sync();
    final laptop = await Device.signIn(email('a11'), 'first password');
    await laptop.sync();

    await AuthFlow(crypto, phone.store).changePassword(phone.api, phone.account, 'first password', 'second password');
    expect(() => laptop.api.sync(0), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    expect(() => Device.signIn(email('a11'), 'first password'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    final again = await Device.signIn(email('a11'), 'second password');
    await again.sync();
    expect((await again.item(id)).password, '1234');
    final unlocked = await AuthFlow(crypto, phone.store).unlock('second password');
    expect(unlocked.accountKey.extractBytes(), phone.account.accountKey.extractBytes());
    expect(() => AuthFlow(crypto, phone.store).unlock('first password'), throwsA(isA<WrongPassword>()));
  });

  test('the recovery key restores the vault on a new device', () async {
    final phone = await Device.signUp(email('a12'), 'forgotten');
    final id = await phone.add('Passport scan notes', password: 'P123');
    await phone.sync();

    final store = await Device._store();
    final api = ApiClient(server);
    final account = await AuthFlow(crypto, store)
        .recover(api, email('a12'), phone.recoveryKey.toLowerCase(), 'brand new', 'tablet');
    final tablet = Device(api, store, account, (await store.account())!.userId);
    await tablet.sync();
    expect((await tablet.item(id)).password, 'P123');
    expect(() => phone.api.sync(0), throwsA(isA<ApiException>()));
    expect(await (await Device.signIn(email('a12'), 'brand new')).api.health(), isTrue);
  });

  test('offline unlock and offline edits sync later', () async {
    final phone = await Device.signUp(email('a13'));
    final flow = AuthFlow(crypto, phone.store);
    final unlocked = await flow.unlock('phone password');
    expect(await flow.token(unlocked), phone.api.token);

    final offline = SyncEngine(ApiClient('http://10.0.2.2:9', timeout: const Duration(seconds: 2)), phone.repo);
    final id = await phone.add('Made offline');
    final report = await offline.sync();
    expect(report.offline, isTrue);
    expect((await phone.entry(id))!.synced, isFalse);
    expect((await phone.sync()).pushed, 1);
  });
}
