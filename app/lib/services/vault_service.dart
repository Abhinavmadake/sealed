import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/api/api_client.dart';
import '../core/api/dto.dart';
import '../core/crypto/account_keys.dart';
import '../core/crypto/sealed_crypto.dart';
import '../core/store/local_store.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/vault_codec.dart';
import '../core/sync/vault_repository.dart';
import '../models/vault_item.dart';
import 'auth_flow.dart';
import 'sharing.dart';

enum VaultStatus { loading, noAccount, locked, unlocked }

const defaultServer = String.fromEnvironment(
  'SEALED_SERVER',
  defaultValue: kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000',
);

String get deviceName {
  if (kIsWeb) return 'Web browser';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android device',
    TargetPlatform.iOS => 'iPhone or iPad',
    TargetPlatform.macOS => 'Mac',
    TargetPlatform.windows => 'Windows PC',
    TargetPlatform.linux => 'Linux PC',
    TargetPlatform.fuchsia => 'Device',
  };
}

class VaultService extends ChangeNotifier with WidgetsBindingObserver {
  VaultService(this.crypto, this.store) : auth = AuthFlow(crypto, store);

  final SealedCrypto crypto;
  final LocalStore store;
  final AuthFlow auth;

  VaultStatus status = VaultStatus.loading;
  AccountRecord? record;
  List<VaultEntry> entries = const [];
  String? pendingRecoveryKey;

  bool syncing = false;
  bool offline = false;
  bool sessionExpired = false;
  DateTime? lastSynced;
  List<String> notices = const [];
  Set<String> conflicts = const {};

  Duration autoLock = const Duration(minutes: 5);
  Duration clipboardClear = const Duration(seconds: 30);

  UnlockedAccount? _account;
  ApiClient? _api;
  VaultRepository? _repo;
  SyncEngine? _engine;
  Sharing? _sharing;
  Timer? _idleTimer;
  DateTime? _pausedAt;

  bool get unlocked => status == VaultStatus.unlocked;
  String get email => record?.email ?? '';
  Uint8List? get publicKey => record?.publicKey;
  String get fingerprint => publicKey == null ? '' : crypto.fingerprint(publicKey!);
  ApiClient get api => _api!;
  Sharing get sharing => _sharing!;
  VaultRepository get repo => _repo!;
  int get pendingCount => entries.where((e) => !e.synced).length;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    final settings = await store.settings();
    autoLock = Duration(seconds: settings['auto_lock_seconds'] as int? ?? 300);
    clipboardClear = Duration(seconds: settings['clipboard_seconds'] as int? ?? 30);
    record = await store.account();
    status = record == null ? VaultStatus.noAccount : VaultStatus.locked;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    super.dispose();
  }

  Future<String> register(String server, String email, String password) async {
    final api = ApiClient(server);
    final (account, recoveryKey) = await auth.register(api, email, password, deviceName);
    pendingRecoveryKey = recoveryKey;
    await _open(account, api);
    return recoveryKey;
  }

  void acknowledgeRecoveryKey() {
    pendingRecoveryKey = null;
    notifyListeners();
  }

  Future<void> login(String server, String email, String password) async {
    final api = ApiClient(server);
    final account = await auth.login(api, email, password, deviceName);
    await _open(account, api);
  }

  Future<void> recover(String server, String email, String recoveryKey, String newPassword) async {
    final api = ApiClient(server);
    final account = await auth.recover(api, email, recoveryKey, newPassword, deviceName);
    await _open(account, api);
  }

  Future<void> unlock(String password) async {
    final account = await auth.unlock(password);
    final api = ApiClient(record!.serverUrl)..token = await auth.token(account);
    await _open(account, api);
  }

  /// Signs in again after the server ended this session, for example after a password change.
  Future<void> reauthenticate(String password) async {
    final account = await auth.login(ApiClient(record!.serverUrl), email, password, deviceName);
    _account?.dispose();
    await _open(account, ApiClient(record!.serverUrl)..token = await auth.token(account));
  }

  Future<void> _open(UnlockedAccount account, ApiClient api) async {
    _account = account;
    _api = api;
    record = await store.account();
    _repo = VaultRepository(store, VaultCodec(crypto, account));
    _engine = SyncEngine(api, _repo!);
    _sharing = Sharing(api, _repo!, record!.userId);
    sessionExpired = api.token == null;
    status = VaultStatus.unlocked;
    touch();
    await refresh();
    unawaited(sync());
  }

  void lock() {
    if (!unlocked) return;
    _idleTimer?.cancel();
    _account?.dispose();
    _account = null;
    _repo = null;
    _engine = null;
    _sharing = null;
    _api = null;
    entries = const [];
    notices = const [];
    pendingRecoveryKey = null;
    status = VaultStatus.locked;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      if (_api?.token != null) await _api!.logout();
    } on Exception {
      // The local data is wiped either way.
    }
    lock();
    await store.clearAll();
    record = null;
    status = VaultStatus.noAccount;
    notifyListeners();
  }

  void touch() {
    _idleTimer?.cancel();
    if (unlocked && autoLock > Duration.zero) _idleTimer = Timer(autoLock, lock);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _pausedAt;
      _pausedAt = null;
      if (since != null && DateTime.now().difference(since) >= autoLock) {
        lock();
      } else {
        touch();
      }
    }
  }

  Future<void> refresh() async {
    if (_repo == null) return;
    final list = await _repo!.entries();
    list.sort((a, b) {
      if (a.item.favorite != b.item.favorite) return a.item.favorite ? -1 : 1;
      return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
    });
    entries = list;
    notifyListeners();
  }

  Future<void> sync() async {
    final engine = _engine;
    if (engine == null || syncing || sessionExpired) return;
    syncing = true;
    notifyListeners();
    try {
      final report = await engine.sync();
      offline = report.offline;
      conflicts = report.conflicts;
      if (report.notices.isNotEmpty) notices = [...notices, ...report.notices];
      if (!report.offline) lastSynced = DateTime.now();
    } on ApiException catch (e) {
      if (e.status == 401) sessionExpired = true;
    } finally {
      syncing = false;
      await refresh();
    }
  }

  void dismissNotices() {
    notices = const [];
    notifyListeners();
  }

  VaultEntry? entry(String id) {
    for (final e in entries) {
      if (e.item.id == id) return e;
    }
    return null;
  }

  Future<void> save(VaultItem item) async {
    await repo.save(item.copyWith(modifiedAt: DateTime.now()));
    await refresh();
    unawaited(sync());
  }

  Future<void> delete(String id) async {
    await repo.delete(id);
    await refresh();
    unawaited(sync());
  }

  Future<ConflictView?> conflict(String id) => repo.conflict(id);

  Future<void> resolve(String id, Map<String, dynamic> chosen) async {
    await repo.resolve(id, chosen);
    await refresh();
    await sync();
  }

  Future<void> share(String id, UserInfo user, String permission) async {
    await sharing.share(id, user, permission);
    await sync();
  }

  Future<void> revoke(String id, String userId) async {
    await sharing.revoke(id, userId);
    await refresh();
  }

  Future<List<SessionInfo>> sessions() => api.sessions();

  Future<void> endSession(String id) => api.endSession(id);

  Future<void> changePassword(String current, String next) async {
    await auth.changePassword(api, _account!, current, next);
    record = await store.account();
    notifyListeners();
  }

  Future<void> updateSettings({Duration? autoLock, Duration? clipboardClear}) async {
    if (autoLock != null) this.autoLock = autoLock;
    if (clipboardClear != null) this.clipboardClear = clipboardClear;
    await store.saveSettings({
      'auto_lock_seconds': this.autoLock.inSeconds,
      'clipboard_seconds': this.clipboardClear.inSeconds,
    });
    touch();
    notifyListeners();
  }
}
