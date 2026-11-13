import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_app/core/api/dto.dart';
import 'package:sealed_app/core/crypto/item_crypto.dart';
import 'package:sealed_app/core/crypto/sealed_crypto.dart';
import 'package:sealed_app/core/store/local_store.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore(await newDatabaseFactoryMemory().openDatabase('t'));
  });

  Uint8List b(int n, [int fill = 7]) => Uint8List.fromList(List.filled(n, fill));

  AccountRecord account({Uint8List? token}) => AccountRecord(
        serverUrl: 'http://10.0.2.2:8000',
        email: 'a@example.com',
        userId: 'u1',
        deviceName: 'phone',
        kdf: KdfParams(salt: b(16), ops: 3, mem: 1 << 28),
        wrappedAccountKey: b(73),
        publicKey: b(32, 1),
        wrappedPrivateKey: b(73, 2),
        sessionId: 's1',
        sealedToken: token,
      );

  test('account record round trip and sign-out', () async {
    expect(await store.account(), isNull);
    await store.saveAccount(account(token: b(50)));
    final back = (await store.account())!;
    expect(back.signedIn, isTrue);
    expect(back.kdf.salt, b(16));
    expect(back.publicKey, b(32, 1));
    await store.saveAccount(back.signedOut());
    expect((await store.account())!.signedIn, isFalse);
  });

  test('remote items and pending changes round trip', () async {
    final remote = RemoteItem(
      id: 'i1',
      revision: 4,
      itemRevision: 3,
      deleted: false,
      ownerId: 'u1',
      blob: b(60),
      permission: 'write',
      keyKind: KeyKind.box,
      wrappedKey: b(73),
      grantedBy: 'u2',
      grantedByEmail: 'b@example.com',
      grantedByPublicKey: b(32),
    );
    await store.putItem(remote);
    final got = (await store.item('i1'))!;
    expect(got.toJson(), remote.toJson());
    expect(got.canWrite, isTrue);
    expect(got.isOwner, isFalse);

    await store.putPending(PendingChange(id: 'i1', op: PendingOp.upsert, payload: b(80), baseRevision: 3));
    final p = (await store.pendingFor('i1'))!;
    expect(p.isNew, isFalse);
    expect(p.inConflict, isFalse);
    final conflicted = p.copyWith(conflictFields: ['password']);
    await store.putPending(conflicted);
    expect((await store.pending())['i1']!.conflictFields, ['password']);
    expect((await store.pending())['i1']!.queuedAt, p.queuedAt);
  });

  test('cursor, pins, and wiping', () async {
    expect(await store.cursor(), 0);
    await store.setCursor(12);
    await store.saveAccount(account());
    await store.pinKey('u2', 'b@example.com', b(32, 9));
    expect(await store.pinnedKey('u2'), b(32, 9));
    await store.putItem(RemoteItem(id: 'x', revision: 1, itemRevision: 1, deleted: false));
    await store.clearVault();
    expect(await store.cursor(), 0);
    expect(await store.items(), isEmpty);
    expect(await store.pinnedKey('u2'), isNull);
    expect(await store.account(), isNotNull);
    await store.clearAll();
    expect(await store.account(), isNull);
  });
}
