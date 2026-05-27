import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../eas/eas_client.dart' show EasException;
import '../eas/mime_builder.dart';
import '../mail/backends/eas_backend.dart';
import '../mail/backends/imap_backend_export.dart';
import '../mail/mail_backend.dart';
import '../mail/mail_exception.dart';
import '../mail/models/mail_account.dart';
import '../mail/models/mail_message.dart';
import '../models/mail_folder.dart';
import '../models/message_layout.dart';
import '../models/message_meta.dart';
import '../utils/platform_support.dart';
import 'account_folder_prefs.dart';
import 'account_storage.dart';
import 'app_settings.dart';
import 'layout_prefs.dart';
import 'message_cache.dart';
import 'message_meta_store.dart';
import 'oauth_service.dart';

class MailSession extends ChangeNotifier {
  MailSession({
    AccountStorage? storage,
    OAuthService? oauth,
    MessageMetaStore? metaStore,
    LayoutPrefs? layoutPrefs,
  })  : _storage = storage ?? AccountStorage(),
        _oauth = oauth ?? OAuthService(),
        _metaStore = metaStore ?? MessageMetaStore(),
        _layoutPrefs = layoutPrefs ?? LayoutPrefs();

  final AccountStorage _storage;
  final OAuthService _oauth;
  final MessageMetaStore _metaStore;
  final LayoutPrefs _layoutPrefs;
  final AppSettings settings = AppSettings();
  final MessageCacheService _cache = MessageCacheService();

  // ── Accounts ──────────────────────────────────────────────────────────────

  List<MailAccount> accounts = [];
  int activeAccountIndex = 0;
  final Map<int, MailBackend> _backends = {};

  MailAccount? get account =>
      accounts.isEmpty ? null : accounts[activeAccountIndex];
  MailBackend? get backend => _backends[activeAccountIndex];

  // ── Messages & folders ────────────────────────────────────────────────────

  List<MailMessage> messages = [];
  List<MailFolder> folders = [];
  String? selectedFolderId;

  /// Unread / total counts per folderId, updated whenever messages load.
  final Map<String, int> _folderUnread = {};
  final Map<String, int> _folderTotal = {};

  int folderUnread(String folderId) => _folderUnread[folderId] ?? 0;
  int folderTotal(String folderId) => _folderTotal[folderId] ?? 0;

  // ── Loading state ─────────────────────────────────────────────────────────

  /// True only on the very first load when no cached messages exist yet.
  bool loading = false;

  /// True while a background sync is in progress.
  bool syncing = false;

  /// True while additional pages are being loaded in the background.
  bool loadingMore = false;

  String? error;

  // ── Body-loading state ────────────────────────────────────────────────────

  final Set<String> _bodyLoading = {};
  bool isBodyLoading(MailMessage m) => _bodyLoading.contains(messageKey(m));

  // ── Layout / selection ────────────────────────────────────────────────────

  final AccountFolderPrefs _folderPrefs = AccountFolderPrefs();
  AccountFolderPrefs get folderPrefs => _folderPrefs;

  MessagePaneLayout paneLayout = MessagePaneLayout.detailRight;
  String? selectedMessageKey;

  Timer? _syncTimer;

  bool get isSignedIn => backend != null;
  bool get isImap => account?.isImap ?? false;
  bool get isEas => account?.isEas ?? false;

  // ── Message helpers ───────────────────────────────────────────────────────

  String messageKey(MailMessage m) =>
      MessageMetaStore.messageKey(m.collectionId, m.serverId);

  MessageMeta metaFor(MailMessage m) => _metaStore.getMeta(messageKey(m));

  List<MailMessage> get sortedMessages {
    final list = List<MailMessage>.from(messages);
    list.sort((a, b) {
      final aPin = metaFor(a).pinned;
      final bPin = metaFor(b).pinned;
      if (aPin != bPin) return aPin ? -1 : 1;
      final ad = a.dateReceived ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.dateReceived ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }

  MailMessage? get selectedMessage {
    if (selectedMessageKey == null) return null;
    for (final m in messages) {
      if (messageKey(m) == selectedMessageKey) return m;
    }
    return null;
  }

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> initAfterLogin() async {
    await _metaStore.load();
    paneLayout = await _layoutPrefs.load();
    if (sortedMessages.isNotEmpty && selectedMessageKey == null) {
      selectedMessageKey = messageKey(sortedMessages.first);
    }
    notifyListeners();
  }

  // ── Message selection ─────────────────────────────────────────────────────

  void selectMessage(MailMessage? message) {
    selectedMessageKey = message == null ? null : messageKey(message);
    notifyListeners();
    if (message != null) {
      markAsRead(message);
      if (message.bodyLoaded) {
        _saveMessageEml(message);
      } else {
        _loadBodyAsync(message);
      }
    }
  }

  Future<void> _loadBodyAsync(MailMessage message) async {
    if (backend == null) return;
    final key = messageKey(message);
    if (_bodyLoading.contains(key)) return;
    _bodyLoading.add(key);
    notifyListeners();

    try {
      final full = await backend!.loadMessageBody(message);
      if (full.bodyLoaded) {
        final idx = messages.indexWhere(
          (m) =>
              m.serverId == message.serverId &&
              m.collectionId == message.collectionId,
        );
        if (idx >= 0) {
          messages[idx] = full;
          _saveCacheForCurrentFolder();
        }
        _saveMessageEml(full);
      }
    } catch (_) {
      // Body load failed; user can retry by re-selecting the message.
    } finally {
      _bodyLoading.remove(key);
      notifyListeners();
    }
  }

  Future<void> markAsRead(MailMessage message) async {
    if (message.read) return;
    final idx = messages.indexWhere(
      (m) =>
          m.serverId == message.serverId &&
          m.collectionId == message.collectionId,
    );
    if (idx >= 0) {
      messages[idx] = message.copyWith(read: true);
      if (selectedFolderId != null) {
        _updateFolderCounts(selectedFolderId!, messages);
      }
      notifyListeners();
    }
    try {
      await backend?.markAsRead(message);
    } catch (_) {}
  }

  Future<void> deleteMessage(MailMessage message) async {
    // Remove from in-memory list immediately.
    final key = messageKey(message);
    messages.removeWhere(
      (m) => m.serverId == message.serverId && m.collectionId == message.collectionId,
    );
    if (selectedMessageKey == key) {
      selectedMessageKey = sortedMessages.isNotEmpty ? messageKey(sortedMessages.first) : null;
    }
    if (selectedFolderId != null) {
      _updateFolderCounts(selectedFolderId!, messages);
    }
    _saveCacheForCurrentFolder();
    notifyListeners();
    // Delete from server in background.
    try {
      await backend?.deleteMessage(message);
    } catch (_) {}
  }

  Future<void> setPaneLayout(MessagePaneLayout layout) async {
    paneLayout = layout;
    await _layoutPrefs.save(layout);
    notifyListeners();
  }

  Future<void> setLabel(
    MailMessage message, {
    required String labelName,
    required int colorValue,
  }) async {
    final key = messageKey(message);
    final meta =
        metaFor(message).copyWith(labelName: labelName, labelColorValue: colorValue);
    await _metaStore.setMeta(key, meta);
    notifyListeners();
  }

  Future<void> clearLabel(MailMessage message) async {
    final key = messageKey(message);
    await _metaStore.setMeta(key, const MessageMeta());
    notifyListeners();
  }

  Future<void> togglePin(MailMessage message) async {
    final key = messageKey(message);
    final meta = metaFor(message);
    await _metaStore.setMeta(key, meta.copyWith(pinned: !meta.pinned));
    notifyListeners();
  }

  // ── Folder selection ──────────────────────────────────────────────────────

  Future<void> selectFolder(String folderId) async {
    if (selectedFolderId == folderId) return;
    selectedFolderId = folderId;
    selectedMessageKey = null;
    notifyListeners();
    if (backend == null) return;
    await _loadFolder(folderId);
  }

  // ── Core folder loading: cache-first + background paging ─────────────────

  Future<void> _loadFolder(String folderId) async {
    if (backend == null) return;

    // 1. Load from cache immediately.
    if (account != null) {
      final cached = await _cache.load(account!.email, folderId);
      if (selectedFolderId != folderId) return;

      if (cached.isNotEmpty) {
        messages = cached;
        _updateFolderCounts(folderId, messages);
        loading = false;
        syncing = true; // show progress while we refresh from server
        notifyListeners();
      } else {
        loading = true;
        syncing = false;
        notifyListeners();
      }
    } else {
      loading = true;
      syncing = false;
      notifyListeners();
    }

    // 2. Server page-1 (newest 50 messages).
    try {
      final batch = await backend!.fetchFolder(folderId, page: 1);
      if (selectedFolderId != folderId) return;

      messages = _mergeMessages(batch, messages);
      _updateFolderCounts(folderId, messages);

      if (selectedMessageKey == null && sortedMessages.isNotEmpty) {
        selectedMessageKey = messageKey(sortedMessages.first);
      }
      _saveCacheForFolder(folderId);
    } on MailException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Ошибка загрузки: ${humanizeConnectionError(e)}';
    } finally {
      loading = false;
      syncing = false;
      notifyListeners();
    }

    // 3. Background paging (pages 2, 3, …).
    _startBackgroundPaging(folderId);
  }

  void _startBackgroundPaging(String folderId) {
    if (loadingMore) return;
    // Fire-and-forget; errors are swallowed.
    _runBackgroundPaging(folderId);
  }

  Future<void> _runBackgroundPaging(String folderId) async {
    if (backend == null) return;
    loadingMore = true;
    notifyListeners();
    try {
      for (int page = 2; ; page++) {
        if (selectedFolderId != folderId || backend == null) break;
        final batch = await backend!.fetchFolder(folderId, page: page);
        if (batch.isEmpty) break;
        if (selectedFolderId != folderId) break;

        messages = _mergeMessages(batch, messages);
        _updateFolderCounts(folderId, messages);
        _saveCacheForFolder(folderId);
        notifyListeners();
        if (batch.length < 50) break; // last page
      }
    } catch (_) {
      // Silent; background errors don't surface to the user.
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  // ── Folder counts ─────────────────────────────────────────────────────────

  void _updateFolderCounts(String folderId, List<MailMessage> msgs) {
    _folderUnread[folderId] = msgs.where((m) => !m.read).length;
    _folderTotal[folderId] = msgs.length;
    // Reflect in the folder list so FolderTreePanel rebuilds.
    final idx = folders.indexWhere((f) => f.id == folderId);
    if (idx >= 0) {
      folders[idx] = folders[idx].copyWith(
        unreadCount: _folderUnread[folderId],
        totalCount: _folderTotal[folderId],
      );
    }
  }

  // ── Message merge ─────────────────────────────────────────────────────────

  /// Server page wins, but preserves an already-loaded body.
  List<MailMessage> _mergeMessages(
    List<MailMessage> serverBatch,
    List<MailMessage> existing,
  ) {
    final byId = <String, MailMessage>{};
    for (final m in existing) {
      byId[m.serverId] = m;
    }
    for (final m in serverBatch) {
      final old = byId[m.serverId];
      if (old != null && old.bodyLoaded && !m.bodyLoaded) {
        // Keep already-loaded body; update read state from server.
        byId[m.serverId] = old.copyWith(read: m.read);
      } else {
        byId[m.serverId] = m;
      }
    }
    final list = byId.values.toList();
    list.sort((a, b) {
      final ad = a.dateReceived ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.dateReceived ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  void _saveCacheForCurrentFolder() {
    if (account != null && selectedFolderId != null) {
      _saveCacheForFolder(selectedFolderId!);
    }
  }

  void _saveCacheForFolder(String folderId) {
    if (account == null) return;
    unawaited(_cache.save(account!.email, folderId, messages));
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    if (backend == null) return;
    if (messages.isNotEmpty) {
      syncing = true;
    } else {
      loading = true;
    }
    error = null;
    notifyListeners();
    try {
      final folderId = selectedFolderId;
      final batch = folderId != null
          ? await backend!.fetchFolder(folderId, page: 1)
          : await backend!.fetchInbox(page: 1);

      messages = _mergeMessages(batch, messages);
      if (folderId != null) _updateFolderCounts(folderId, messages);

      if (selectedMessageKey != null &&
          !messages.any((m) => messageKey(m) == selectedMessageKey)) {
        selectedMessageKey =
            messages.isNotEmpty ? messageKey(sortedMessages.first) : null;
      }
      _saveCacheForCurrentFolder();
    } on MailException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Ошибка синхронизации: ${humanizeConnectionError(e)}';
    } finally {
      loading = false;
      syncing = false;
      notifyListeners();
    }
  }

  // ── Multiple accounts ─────────────────────────────────────────────────────

  Future<void> switchAccount(int index) async {
    if (index < 0 || index >= accounts.length) return;
    activeAccountIndex = index;
    await _storage.saveActiveIndex(index);

    messages = [];
    folders = [];
    selectedFolderId = null;
    selectedMessageKey = null;
    error = null;
    _folderUnread.clear();
    _folderTotal.clear();
    notifyListeners();

    if (_backends.containsKey(index)) {
      await _reloadWithExistingBackend(index);
    } else {
      await _connectAndLoad(index);
    }
    _restartSyncTimer();
  }

  Future<void> _reloadWithExistingBackend(int index) async {
    loading = true;
    notifyListeners();
    try {
      final b = _backends[index]!;
      folders = await b.fetchFolders();
      await _folderPrefs.load(accounts[index].email);
      final folderId =
          folders.where((f) => f.isInbox).firstOrNull?.id ?? 'INBOX';
      selectedFolderId = folderId;
      loading = false;
      notifyListeners();
      await _loadFolder(folderId);
      await initAfterLogin();
    } catch (e) {
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }

  Future<void> removeAccount(int index) async {
    if (index < 0 || index >= accounts.length) return;
    await _backends[index]?.disconnect();
    _backends.remove(index);

    // Re-index remaining backends.
    final newBackends = <int, MailBackend>{};
    for (final entry in _backends.entries) {
      final newIdx = entry.key > index ? entry.key - 1 : entry.key;
      newBackends[newIdx] = entry.value;
    }
    _backends
      ..clear()
      ..addAll(newBackends);

    accounts.removeAt(index);

    if (activeAccountIndex >= accounts.length) {
      activeAccountIndex = accounts.isEmpty ? 0 : accounts.length - 1;
    }
    await _storage.saveAll(accounts);
    await _storage.saveActiveIndex(activeAccountIndex);

    if (accounts.isEmpty) {
      messages = [];
      folders = [];
      selectedFolderId = null;
      selectedMessageKey = null;
      notifyListeners();
    } else {
      await switchAccount(activeAccountIndex);
    }
  }

  Future<void> updateAccount(int index, MailAccount updated) async {
    if (index < 0 || index >= accounts.length) return;
    accounts[index] = updated;
    await _storage.saveAll(accounts);
    notifyListeners();
  }

  Future<void> reconnectAccount(int index, MailAccount updated) async {
    if (index < 0 || index >= accounts.length) return;
    accounts[index] = updated;
    await _storage.saveAll(accounts);
    if (index == activeAccountIndex) {
      await _connectAndLoad(index);
    }
  }

  Future<void> updateFolderPrefs(
      {List<String>? order, Set<String>? hidden}) async {
    if (account == null) return;
    if (order != null) await _folderPrefs.saveOrder(account!.email, order);
    if (hidden != null) await _folderPrefs.saveHidden(account!.email, hidden);
    notifyListeners();
  }

  // ── Session restore / sign-in ─────────────────────────────────────────────

  Future<void> restoreSession() async {
    loading = true;
    await settings.load();
    await _metaStore.load();

    accounts = await _storage.loadAll();
    if (accounts.isEmpty) {
      loading = false;
      notifyListeners();
      return;
    }

    var savedIdx = await _storage.loadActiveIndex();
    if (savedIdx >= accounts.length) savedIdx = 0;
    activeAccountIndex = savedIdx;
    paneLayout = await _layoutPrefs.load();

    await _connectAndLoad(activeAccountIndex);
    _restartSyncTimer();
  }

  Future<void> _connectAndLoad(int index) async {
    if (index >= accounts.length) return;
    final acc = accounts[index];
    error = null;

    // Show cached inbox immediately so the UI is not blank while connecting.
    const tempInbox = 'INBOX';
    final cachedEarly = await _cache.load(acc.email, tempInbox);
    if (cachedEarly.isNotEmpty && index == activeAccountIndex) {
      messages = cachedEarly;
      selectedFolderId = tempInbox;
      _updateFolderCounts(tempInbox, messages);
      loading = false;
      syncing = true;
      notifyListeners();
    } else {
      loading = true;
      syncing = false;
      notifyListeners();
    }

    try {
      // Refresh OAuth token if needed.
      MailAccount effectiveAcc = acc;
      if (acc.isEas &&
          acc.usesOAuth &&
          acc.refreshToken != null &&
          _tokenNeedsRefresh(acc)) {
        final tokens = await _oauth.refresh(acc.refreshToken!);
        if (tokens != null) {
          effectiveAcc = acc.copyWith(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            tokenExpiresAt: tokens.accessTokenExpiration,
          );
          accounts[index] = effectiveAcc;
          await _storage.saveAll(accounts);
        }
      }

      await _backends[index]?.disconnect();

      final blocked = connectionBlockedReason(imap: effectiveAcc.isImap);
      if (blocked != null) throw MailException(blocked);

      final b = effectiveAcc.isImap
          ? ImapMailBackend() as MailBackend
          : EasMailBackend();
      // IMAP: use autodiscover so we always get the correct SMTP host/port,
      // even when the user entered approximate settings at sign-in time.
      await b.connect(
        effectiveAcc,
        useAutodiscover: effectiveAcc.isImap,
      );
      _backends[index] = b;

      if (b is EasMailBackend && b.lastServerUrl != null) {
        final updated = effectiveAcc.copyWith(serverUrl: b.lastServerUrl);
        accounts[index] = updated;
        await _storage.saveAll(accounts);
      }

      // Persist resolved IMAP/SMTP settings so future reconnects use the
      // correct server addresses (especially important when autodiscover
      // found a different SMTP host than what the user entered).
      if (b is ImapMailBackend) {
        _saveResolvedImapSettings(index, effectiveAcc, b);
      }

      if (index == activeAccountIndex) {
        folders = await b.fetchFolders();
        await _folderPrefs.load(accounts[index].email);
        final folderId =
            folders.where((f) => f.isInbox).firstOrNull?.id ?? 'INBOX';
        selectedFolderId = folderId;

        // Show the real folder ID (may differ from 'INBOX').
        loading = false;
        syncing = false;
        notifyListeners();

        await _loadFolder(folderId);
        await initAfterLogin();
      }
    } on MailException catch (e) {
      error = e.message;
    } on EasException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Ошибка подключения: ${humanizeConnectionError(e)}';
    } finally {
      loading = false;
      syncing = false;
      notifyListeners();
    }
  }

  bool _tokenNeedsRefresh(MailAccount acc) {
    if (acc.tokenExpiresAt == null) return false;
    return acc.tokenExpiresAt!
        .isBefore(DateTime.now().add(const Duration(minutes: 5)));
  }

  Future<void> signInWithOAuth({String? serverHint}) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final tokens = await _oauth.signIn();
      final email = _emailFromToken(tokens.accessToken);
      if (email == null || email.isEmpty) {
        throw Exception('Не удалось определить email из токена');
      }

      final host = serverHint?.trim().isNotEmpty == true
          ? serverHint!.trim()
          : (email.contains('@') ? 'outlook.office365.com' : email);

      final acc = MailAccount(
        email: email,
        password: '',
        serverUrl: host,
        authType: EasAuthType.oauth,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        tokenExpiresAt: tokens.accessTokenExpiration,
        protocol: MailProtocol.eas,
      );
      await signIn(acc, useAutodiscover: true);
    } catch (e) {
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }

  Future<void> signIn(MailAccount acc,
      {bool useAutodiscover = true}) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final blocked = connectionBlockedReason(imap: acc.isImap);
      if (blocked != null) throw MailException(blocked);

      final existing = accounts.indexWhere((a) => a.email == acc.email);
      final idx = existing >= 0 ? existing : accounts.length;

      if (existing < 0) {
        accounts.add(acc);
      } else {
        accounts[existing] = acc;
      }
      activeAccountIndex = idx;

      await _backends[idx]?.disconnect();

      final b = acc.isImap
          ? ImapMailBackend() as MailBackend
          : EasMailBackend();
      await b.connect(acc, useAutodiscover: useAutodiscover);
      _backends[idx] = b;

      MailAccount effectiveAcc = acc;
      if (b is EasMailBackend) {
        effectiveAcc =
            acc.copyWith(serverUrl: b.lastServerUrl ?? acc.serverUrl);
        accounts[idx] = effectiveAcc;
      }
      // Persist resolved IMAP/SMTP settings (autodiscover may have found
      // a different SMTP host than what the user typed).
      if (b is ImapMailBackend) {
        effectiveAcc = _applyResolvedImapSettings(effectiveAcc, b);
        accounts[idx] = effectiveAcc;
      }

      await _storage.saveAll(accounts);
      await _storage.saveActiveIndex(activeAccountIndex);

      folders = await b.fetchFolders();
      await _folderPrefs.load(effectiveAcc.email);
      final folderId =
          folders.where((f) => f.isInbox).firstOrNull?.id ?? 'INBOX';
      selectedFolderId = folderId;

      loading = false;
      notifyListeners();

      await _loadFolder(folderId);
      await initAfterLogin();

      _restartSyncTimer();
    } on MailException catch (e) {
      error = e.message;
    } on EasException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Ошибка подключения: ${humanizeConnectionError(e)}';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Send mail ─────────────────────────────────────────────────────────────

  Future<void> sendMail({
    required String to,
    required String subject,
    required String bodyHtml,
    List<MimeAttachment>? attachments,
  }) async {
    if (backend == null || account == null) {
      throw const MailException('Нет подключения');
    }
    await backend!.sendMail(
      account: account!,
      to: to,
      subject: subject,
      body: bodyHtml,
      attachments: attachments,
      isHtml: true,
    );
    await refresh();
  }

  Future<String> downloadAttachment({
    required MailMessage message,
    required int attachmentIndex,
  }) async {
    if (backend == null) throw const MailException('Нет подключения');
    return backend!.downloadAttachment(
      message: message,
      attachmentIndex: attachmentIndex,
    );
  }

  Future<Uint8List> loadAttachmentBytes({
    required MailMessage message,
    required int attachmentIndex,
  }) async {
    if (backend == null) throw const MailException('Нет подключения');
    return backend!.loadAttachmentBytes(
      message: message,
      attachmentIndex: attachmentIndex,
    );
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    for (final b in _backends.values) {
      try {
        await b.disconnect();
      } catch (_) {}
    }
    _backends.clear();
    await _storage.clear();
    accounts = [];
    activeAccountIndex = 0;
    messages = [];
    folders = [];
    selectedFolderId = null;
    selectedMessageKey = null;
    error = null;
    _folderUnread.clear();
    _folderTotal.clear();
    notifyListeners();
  }

  // ── Sync timer ────────────────────────────────────────────────────────────

  void _restartSyncTimer() {
    _syncTimer?.cancel();
    final interval = settings.syncIntervalSeconds;
    if (interval <= 0 || !isSignedIn) return;
    _syncTimer =
        Timer.periodic(Duration(seconds: interval), (_) => refresh());
  }

  Future<void> updateSyncInterval(int seconds) async {
    await settings.setSyncInterval(seconds);
    _restartSyncTimer();
    notifyListeners();
  }

  // ── Local .eml storage ────────────────────────────────────────────────────

  Future<void> _saveMessageEml(MailMessage message) async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeEmail = (account?.email ?? 'unknown')
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final mailDir = Directory(p.join(dir.path, 'mail', safeEmail));
      await mailDir.create(recursive: true);

      final safeName =
          message.serverId.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final file = File(p.join(mailDir.path, '$safeName.eml'));
      if (await file.exists()) return;

      await file.writeAsString(_buildEml(message));
    } catch (_) {}
  }

  String _buildEml(MailMessage message) {
    final buf = StringBuffer();
    buf.writeln('From: ${message.from}');
    if (message.to != null) buf.writeln('To: ${message.to}');
    buf.writeln('Subject: ${message.subject}');
    if (message.dateReceived != null) {
      buf.writeln('Date: ${_formatRfc2822(message.dateReceived!)}');
    }
    buf.writeln('MIME-Version: 1.0');
    if (message.hasHtmlBody) {
      buf.writeln('Content-Type: text/html; charset=UTF-8');
      buf.writeln();
      buf.writeln(message.bodyHtml ?? '');
    } else {
      buf.writeln('Content-Type: text/plain; charset=UTF-8');
      buf.writeln();
      buf.writeln(message.body ?? '');
    }
    return buf.toString();
  }

  String _formatRfc2822(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final utc = dt.toUtc();
    return '${days[utc.weekday - 1]}, ${utc.day.toString().padLeft(2, '0')} '
        '${months[utc.month - 1]} ${utc.year} '
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')} +0000';
  }

  // ── OAuth helpers ─────────────────────────────────────────────────────────

  String? _emailFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = parts[1];
      final normalized = _base64Normalize(payload);
      final json = utf8.decode(base64.decode(normalized));
      final map = jsonDecode(json) as Map<String, dynamic>;
      return (map['preferred_username'] ?? map['upn'] ?? map['email'])
          as String?;
    } catch (_) {
      return null;
    }
  }

  String _base64Normalize(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return s;
  }

  // ── IMAP resolved-settings helpers ───────────────────────────────────────

  /// Returns [acc] updated with any autodiscovered IMAP/SMTP host+port.
  MailAccount _applyResolvedImapSettings(
      MailAccount acc, ImapMailBackend b) {
    final smtpHost = b.resolvedSmtpHost;
    final smtpPort = b.resolvedSmtpPort;
    final imapHost = b.resolvedImapHost;
    final imapPort = b.resolvedImapPort;
    if (smtpHost == null && imapHost == null) return acc;
    return acc.copyWith(
      smtpHost: (smtpHost != null && smtpHost.isNotEmpty) ? smtpHost : null,
      smtpPort: smtpPort,
      imapHost: (imapHost != null && imapHost.isNotEmpty) ? imapHost : null,
      imapPort: imapPort,
    );
  }

  /// Saves resolved settings for account [index] if they differ from stored.
  Future<void> _saveResolvedImapSettings(
      int index, MailAccount current, ImapMailBackend b) async {
    final updated = _applyResolvedImapSettings(current, b);
    if (updated.smtpHost == current.smtpHost &&
        updated.smtpPort == current.smtpPort &&
        updated.imapHost == current.imapHost &&
        updated.imapPort == current.imapPort) {
      return; // nothing changed
    }
    accounts[index] = updated;
    await _storage.saveAll(accounts);
  }
}
