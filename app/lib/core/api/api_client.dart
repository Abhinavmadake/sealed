import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../crypto/account_keys.dart';
import '../crypto/sealed_crypto.dart';
import 'dto.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, [this.body]);

  final int status;
  final String message;
  final Map<String, dynamic>? body;

  @override
  String toString() => message;
}

class ConflictException extends ApiException {
  ConflictException(String message, this.current, Map<String, dynamic>? body) : super(409, message, body);

  final RemoteItem? current;
}

class OfflineException implements Exception {
  @override
  String toString() => 'Cannot reach the server';
}

class ApiClient {
  ApiClient(String baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 15)})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _http;
  String? token;

  Future<Map<String, dynamic>?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: query);
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    // ngrok's free tunnels answer browsers with a warning page unless this is set.
    if (kIsWeb) request.headers['ngrok-skip-browser-warning'] = '1';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw OfflineException();
    } on http.ClientException {
      throw OfflineException();
    }
    Map<String, dynamic>? data;
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
        if (decoded is List) data = {'items': decoded};
      } on FormatException {
        data = null;
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final message = _message(response.statusCode, data);
    if (response.statusCode == 409) {
      final current = data?['current'];
      throw ConflictException(
          message, current is Map<String, dynamic> ? RemoteItem.fromJson(current) : null, data);
    }
    throw ApiException(response.statusCode, message, data);
  }

  String _message(int status, Map<String, dynamic>? data) {
    final detail = data?['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty && detail.first is Map) {
      return (detail.first as Map)['msg']?.toString() ?? 'Request rejected';
    }
    return switch (status) {
      401 => 'Not signed in',
      429 => 'Too many attempts, try again later',
      _ => 'Server error ($status)',
    };
  }

  String _b64(Uint8List bytes) => base64Encode(bytes);

  Future<bool> health() async {
    try {
      return (await _send('GET', '/health'))?['status'] == 'ok';
    } on Exception {
      return false;
    }
  }

  Future<KdfParams> prelogin(String email) async =>
      kdfFromJson((await _send('POST', '/auth/prelogin', body: {'email': email}))!);

  Future<LoginResponse> register(String email, RegistrationMaterial m, String deviceName) async {
    final data = await _send('POST', '/auth/register', body: {
      'email': email,
      'auth_key': _b64(m.password.authKey),
      ...kdfToJson(m.password.kdf),
      'wrapped_account_key': _b64(m.password.wrappedAccountKey),
      'public_key': _b64(m.account.publicKey),
      'wrapped_private_key': _b64(m.wrappedPrivateKey),
      'recovery_auth': _b64(m.recoveryAuth),
      'recovery_wrapped_key': _b64(m.recoveryWrappedKey),
      'device_name': deviceName,
    });
    return LoginResponse.fromJson(data!);
  }

  Future<LoginResponse> login(String email, Uint8List authKey, String deviceName) async {
    final data = await _send('POST', '/auth/login',
        body: {'email': email, 'auth_key': _b64(authKey), 'device_name': deviceName});
    return LoginResponse.fromJson(data!);
  }

  Future<void> logout() => _send('POST', '/auth/logout');

  Future<void> changePassword(Uint8List currentAuthKey, PasswordMaterial m) => _send(
        'POST',
        '/auth/change-password',
        body: {
          'current_auth_key': _b64(currentAuthKey),
          'new_auth_key': _b64(m.authKey),
          ...kdfToJson(m.kdf),
          'wrapped_account_key': _b64(m.wrappedAccountKey),
        },
      );

  Future<Uint8List> recoverStart(String email, Uint8List recoveryAuth) async {
    final data = await _send('POST', '/auth/recover/start',
        body: {'email': email, 'recovery_auth': _b64(recoveryAuth)});
    return base64Decode(data!['recovery_wrapped_key'] as String);
  }

  Future<LoginResponse> recoverFinish(
      String email, Uint8List recoveryAuth, PasswordMaterial m, String deviceName) async {
    final data = await _send('POST', '/auth/recover/finish', body: {
      'email': email,
      'recovery_auth': _b64(recoveryAuth),
      'new_auth_key': _b64(m.authKey),
      ...kdfToJson(m.kdf),
      'wrapped_account_key': _b64(m.wrappedAccountKey),
      'device_name': deviceName,
    });
    return LoginResponse.fromJson(data!);
  }

  Future<List<SessionInfo>> sessions() async {
    final data = await _send('GET', '/sessions');
    return [for (final s in data!['items'] as List) SessionInfo.fromJson(s as Map<String, dynamic>)];
  }

  Future<void> endSession(String id) => _send('DELETE', '/sessions/$id');

  Future<(int, List<RemoteItem>)> sync(int since) async {
    final data = await _send('GET', '/sync', query: {'since': '$since'});
    return (
      data!['revision'] as int,
      [for (final i in data['items'] as List) RemoteItem.fromJson(i as Map<String, dynamic>)],
    );
  }

  Future<RemoteItem> putItem(String id, Uint8List blob, {int? baseRevision, Uint8List? wrappedKey}) async {
    final data = await _send('PUT', '/items/$id', body: {
      'blob': _b64(blob),
      'base_revision': baseRevision,
      if (wrappedKey != null) 'wrapped_key': _b64(wrappedKey),
    });
    return RemoteItem.fromJson(data!);
  }

  Future<void> deleteItem(String id, int baseRevision) =>
      _send('DELETE', '/items/$id', query: {'base_revision': '$baseRevision'});

  Future<UserInfo?> lookup(String email) async {
    try {
      return UserInfo.fromJson((await _send('GET', '/users/lookup', query: {'email': email}))!);
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<List<GrantInfo>> grants(String itemId) async {
    final data = await _send('GET', '/items/$itemId/grants');
    return [for (final g in data!['items'] as List) GrantInfo.fromJson(g as Map<String, dynamic>)];
  }

  Future<void> addGrant(String itemId, String userId, Uint8List wrappedKey, String permission) => _send(
        'POST',
        '/items/$itemId/grants',
        body: {'user_id': userId, 'wrapped_key': _b64(wrappedKey), 'permission': permission},
      );

  Future<RemoteItem> revoke(
    String itemId, {
    required String userId,
    required int baseRevision,
    required Uint8List blob,
    required Map<String, Uint8List> rewrapped,
  }) async {
    final data = await _send('POST', '/items/$itemId/revoke', body: {
      'user_id': userId,
      'base_revision': baseRevision,
      'blob': _b64(blob),
      'grants': [
        for (final e in rewrapped.entries) {'user_id': e.key, 'wrapped_key': _b64(e.value)},
      ],
    });
    return RemoteItem.fromJson(data!);
  }

  void close() => _http.close();
}
