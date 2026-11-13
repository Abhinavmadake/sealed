import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricCancelled implements Exception {}

/// Keeps a copy of the account key under an Android Keystore key that only a fingerprint releases.
class BiometricKeyStore {
  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      enforceBiometrics: true,
      requireBiometricsPerOperation: true,
      biometricType: AndroidBiometricType.strongBiometricOnly,
      requireBiometricConfirmation: false,
      storageNamespace: 'sealed_biometric',
      migrateOnAlgorithmChange: false,
      biometricPromptSubtitle: 'Confirm your fingerprint',
      biometricPromptTitle: 'Unlock Sealed',
      biometricPromptNegativeButton: 'Use master password',
    ),
  );

  // BiometricPrompt codes for cancelled, user cancelled and the negative button.
  static const _cancelCodes = {'5', '10', '13'};
  static final _errorCode = RegExp(r'authentication error \[(\d+)\]');

  String _name(String userId) => 'account_key_$userId';

  Future<bool> available() async {
    if (!_supported) return false;
    try {
      return (await LocalAuthentication().getAvailableBiometrics()).isNotEmpty;
    } on Exception {
      return false;
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      final code = _errorCode.firstMatch('${e.message} ${e.details}')?.group(1);
      if (_cancelCodes.contains(code)) throw BiometricCancelled();
      rethrow;
    }
  }

  Future<void> save(String userId, Uint8List accountKey) =>
      _guard(() => _storage.write(key: _name(userId), value: base64Encode(accountKey)));

  Future<Uint8List?> load(String userId) => _guard(() async {
        final value = await _storage.read(key: _name(userId));
        return value == null ? null : base64Decode(value);
      });

  Future<void> clear(String userId) async {
    if (!_supported) return;
    try {
      await _storage.deleteAll();
    } on Exception {
      // Nothing stored, or the Keystore key is already gone.
    }
  }
}
