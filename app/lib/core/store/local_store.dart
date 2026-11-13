import 'dart:convert';
import 'dart:typed_data';

import 'package:sembast/sembast.dart';

import '../api/dto.dart';
import '../crypto/sealed_crypto.dart';

Uint8List? _bytes(Object? value) => value == null ? null : base64Decode(value as String);
String? _b64(Uint8List? value) => value == null ? null : base64Encode(value);

class AccountRecord {
  AccountRecord({
    required this.serverUrl,
    required this.email,
    required this.userId,
    required this.deviceName,
    required this.kdf,
    required this.wrappedAccountKey,
    required this.publicKey,
    required this.wrappedPrivateKey,
    this.sessionId,
    this.sealedToken,
  });

  final String serverUrl;
  final String email;
  final String userId;
  final String deviceName;
  final KdfParams kdf;
  final Uint8List wrappedAccountKey;
  final Uint8List publicKey;
  final Uint8List wrappedPrivateKey;
  final String? sessionId;
  final Uint8List? sealedToken;

  bool get signedIn => sealedToken != null;

  AccountRecord signedOut() => AccountRecord(
        serverUrl: serverUrl,
        email: email,
        userId: userId,
        deviceName: deviceName,
        kdf: kdf,
        wrappedAccountKey: wrappedAccountKey,
        publicKey: publicKey,
        wrappedPrivateKey: wrappedPrivateKey,
      );

  Map<String, Object?> toJson() => {
        'server_url': serverUrl,
        'email': email,
        'user_id': userId,
        'device_name': deviceName,
        ...kdfToJson(kdf),
        'wrapped_account_key': _b64(wrappedAccountKey),
        'public_key': _b64(publicKey),
        'wrapped_private_key': _b64(wrappedPrivateKey),
        'session_id': sessionId,
        'sealed_token': _b64(sealedToken),
      };

  factory AccountRecord.fromJson(Map<String, Object?> json) => AccountRecord(
        serverUrl: json['server_url'] as String,
        email: json['email'] as String,
        userId: json['user_id'] as String,
        deviceName: json['device_name'] as String,
        kdf: kdfFromJson(Map<String, dynamic>.from(json)),
        wrappedAccountKey: _bytes(json['wrapped_account_key'])!,
        publicKey: _bytes(json['public_key'])!,
        wrappedPrivateKey: _bytes(json['wrapped_private_key'])!,
        sessionId: json['session_id'] as String?,
        sealedToken: _bytes(json['sealed_token']),
      );
}

enum PendingOp { upsert, delete }

class PendingChange {
  PendingChange({
    required this.id,
    required this.op,
    this.payload,
    this.base,
    this.baseRevision,
    this.wrappedKey,
    this.conflictFields = const [],
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now().toUtc();

  final String id;
  final PendingOp op;
  final Uint8List? payload;
  final Uint8List? base;
  final int? baseRevision;
  final Uint8List? wrappedKey;
  final List<String> conflictFields;
  final DateTime queuedAt;

  bool get isNew => baseRevision == null;
  bool get inConflict => conflictFields.isNotEmpty;

  PendingChange copyWith({
    Uint8List? payload,
    Uint8List? base,
    int? baseRevision,
    List<String>? conflictFields,
    bool dropWrappedKey = false,
  }) =>
      PendingChange(
        id: id,
        op: op,
        payload: payload ?? this.payload,
        base: base ?? this.base,
        baseRevision: baseRevision ?? this.baseRevision,
        wrappedKey: dropWrappedKey ? null : wrappedKey,
        conflictFields: conflictFields ?? this.conflictFields,
        queuedAt: queuedAt,
      );

  Map<String, Object?> toJson() => {
        'op': op.name,
        'payload': _b64(payload),
        'base': _b64(base),
        'base_revision': baseRevision,
        'wrapped_key': _b64(wrappedKey),
        'conflict_fields': conflictFields,
        'queued_at': queuedAt.toIso8601String(),
      };

  factory PendingChange.fromJson(String id, Map<String, Object?> json) => PendingChange(
        id: id,
        op: PendingOp.values.byName(json['op'] as String),
        payload: _bytes(json['payload']),
        base: _bytes(json['base']),
        baseRevision: json['base_revision'] as int?,
        wrappedKey: _bytes(json['wrapped_key']),
        conflictFields: [for (final f in (json['conflict_fields'] as List? ?? const [])) f as String],
        queuedAt: DateTime.parse(json['queued_at'] as String),
      );
}

/// Everything stored here is either ciphertext or harmless metadata.
class LocalStore {
  LocalStore(this.db);

  final Database db;

  final _meta = StoreRef<String, Object?>('meta');
  final _items = stringMapStoreFactory.store('items');
  final _pending = stringMapStoreFactory.store('pending');
  final _pins = stringMapStoreFactory.store('pins');

  Future<AccountRecord?> account() async {
    final json = await _meta.record('account').get(db);
    return json == null ? null : AccountRecord.fromJson(Map<String, Object?>.from(json as Map));
  }

  Future<void> saveAccount(AccountRecord account) => _meta.record('account').put(db, account.toJson());

  Future<int> cursor() async => (await _meta.record('cursor').get(db)) as int? ?? 0;

  Future<void> setCursor(int value) => _meta.record('cursor').put(db, value);

  Future<Map<String, Object?>> settings() async =>
      Map<String, Object?>.from((await _meta.record('settings').get(db)) as Map? ?? const {});

  Future<void> saveSettings(Map<String, Object?> value) => _meta.record('settings').put(db, value);

  Future<Map<String, RemoteItem>> items() async => {
        for (final r in await _items.find(db))
          r.key: RemoteItem.fromJson(Map<String, dynamic>.from(r.value)),
      };

  Future<RemoteItem?> item(String id) async {
    final json = await _items.record(id).get(db);
    return json == null ? null : RemoteItem.fromJson(Map<String, dynamic>.from(json));
  }

  Future<void> putItem(RemoteItem item) => _items.record(item.id).put(db, item.toJson());

  Future<void> removeItem(String id) => _items.record(id).delete(db);

  Future<Map<String, PendingChange>> pending() async => {
        for (final r in await _pending.find(db)) r.key: PendingChange.fromJson(r.key, r.value),
      };

  Future<PendingChange?> pendingFor(String id) async {
    final json = await _pending.record(id).get(db);
    return json == null ? null : PendingChange.fromJson(id, json);
  }

  Future<void> putPending(PendingChange change) => _pending.record(change.id).put(db, change.toJson());

  Future<void> removePending(String id) => _pending.record(id).delete(db);

  Future<Uint8List?> pinnedKey(String userId) async =>
      _bytes((await _pins.record(userId).get(db))?['public_key']);

  Future<void> pinKey(String userId, String email, Uint8List publicKey) =>
      _pins.record(userId).put(db, {'email': email, 'public_key': _b64(publicKey)});

  Future<void> clearVault() async {
    await db.transaction((txn) async {
      await _items.delete(txn);
      await _pending.delete(txn);
      await _pins.delete(txn);
      await _meta.record('cursor').delete(txn);
    });
  }

  Future<void> clearAll() async {
    await clearVault();
    await _meta.record('account').delete(db);
  }
}
