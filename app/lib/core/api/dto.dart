import 'dart:convert';
import 'dart:typed_data';

import '../crypto/item_crypto.dart';
import '../crypto/sealed_crypto.dart';

Uint8List? _bytes(Object? value) => value == null ? null : base64Decode(value as String);
String? _b64(Uint8List? value) => value == null ? null : base64Encode(value);

class RemoteItem {
  RemoteItem({
    required this.id,
    required this.revision,
    required this.itemRevision,
    required this.deleted,
    this.ownerId,
    this.blob,
    this.permission,
    this.keyKind,
    this.wrappedKey,
    this.grantedBy,
    this.grantedByEmail,
    this.grantedByPublicKey,
  });

  final String id;
  final int revision;
  final int itemRevision;
  final bool deleted;
  final String? ownerId;
  final Uint8List? blob;
  final String? permission;
  final KeyKind? keyKind;
  final Uint8List? wrappedKey;
  final String? grantedBy;
  final String? grantedByEmail;
  final Uint8List? grantedByPublicKey;

  bool get isOwner => permission == 'owner';
  bool get canWrite => permission == 'owner' || permission == 'write';

  factory RemoteItem.fromJson(Map<String, dynamic> json) => RemoteItem(
        id: json['id'] as String,
        revision: json['revision'] as int,
        itemRevision: json['item_revision'] as int,
        deleted: json['deleted'] as bool,
        ownerId: json['owner_id'] as String?,
        blob: _bytes(json['blob']),
        permission: json['permission'] as String?,
        keyKind: switch (json['key_kind']) {
          'self' => KeyKind.self,
          'box' => KeyKind.box,
          _ => null,
        },
        wrappedKey: _bytes(json['wrapped_key']),
        grantedBy: json['granted_by'] as String?,
        grantedByEmail: json['granted_by_email'] as String?,
        grantedByPublicKey: _bytes(json['granted_by_public_key']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'revision': revision,
        'item_revision': itemRevision,
        'deleted': deleted,
        'owner_id': ownerId,
        'blob': _b64(blob),
        'permission': permission,
        'key_kind': keyKind?.name,
        'wrapped_key': _b64(wrappedKey),
        'granted_by': grantedBy,
        'granted_by_email': grantedByEmail,
        'granted_by_public_key': _b64(grantedByPublicKey),
      };
}

class LoginResponse {
  LoginResponse({
    required this.token,
    required this.sessionId,
    required this.userId,
    required this.email,
    required this.kdf,
    required this.wrappedAccountKey,
    required this.publicKey,
    required this.wrappedPrivateKey,
  });

  final String token;
  final String sessionId;
  final String userId;
  final String email;
  final KdfParams kdf;
  final Uint8List wrappedAccountKey;
  final Uint8List publicKey;
  final Uint8List wrappedPrivateKey;

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
        token: json['token'] as String,
        sessionId: json['session_id'] as String,
        userId: json['user_id'] as String,
        email: json['email'] as String,
        kdf: kdfFromJson(json),
        wrappedAccountKey: _bytes(json['wrapped_account_key'])!,
        publicKey: _bytes(json['public_key'])!,
        wrappedPrivateKey: _bytes(json['wrapped_private_key'])!,
      );
}

KdfParams kdfFromJson(Map<String, dynamic> json) => KdfParams(
      salt: _bytes(json['kdf_salt'])!,
      ops: json['kdf_ops'] as int,
      mem: json['kdf_mem'] as int,
    );

Map<String, dynamic> kdfToJson(KdfParams kdf) =>
    {'kdf_salt': base64Encode(kdf.salt), 'kdf_ops': kdf.ops, 'kdf_mem': kdf.mem};

class SessionInfo {
  SessionInfo(this.id, this.deviceName, this.createdAt, this.lastSeenAt, this.current);

  final String id;
  final String deviceName;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final bool current;

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
        json['id'] as String,
        json['device_name'] as String,
        DateTime.parse(json['created_at'] as String),
        DateTime.parse(json['last_seen_at'] as String),
        json['current'] as bool,
      );
}

class UserInfo {
  UserInfo(this.id, this.email, this.publicKey);

  final String id;
  final String email;
  final Uint8List publicKey;

  factory UserInfo.fromJson(Map<String, dynamic> json) =>
      UserInfo(json['id'] as String, json['email'] as String, _bytes(json['public_key'])!);
}

class GrantInfo {
  GrantInfo(this.user, this.permission, this.keyKind);

  final UserInfo user;
  final String permission;
  final String keyKind;

  factory GrantInfo.fromJson(Map<String, dynamic> json) => GrantInfo(
        UserInfo(json['user_id'] as String, json['email'] as String, _bytes(json['public_key'])!),
        json['permission'] as String,
        json['key_kind'] as String,
      );
}
