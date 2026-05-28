import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as em;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../eas/mime_builder.dart';
import '../../models/mail_folder.dart';
import '../mail_exception.dart';
import '../mail_backend.dart';
import '../models/mail_account.dart';
import '../models/mail_attachment.dart';
import '../models/mail_message.dart';

class ImapMailBackend implements MailBackend {
  em.MailClient? _client;

  /// UID → envelope MimeMessage (populated during folder fetch).
  final Map<String, em.MimeMessage> _msgCache = {};
  List<em.Mailbox> _mailboxes = [];

  static const int _batchSize = 50;

  // ── Resolved server settings (filled after connect, may differ from
  //    user-entered settings when autodiscover succeeded) ──────────────────

  String? resolvedImapHost;
  int? resolvedImapPort;
  String? resolvedSmtpHost;
  int? resolvedSmtpPort;

  // ── Connect ──────────────────────────────────────────────────────────────

  @override
  Future<void> connect(
    MailAccount account, {
    bool useAutodiscover = true,
  }) async {
    em.MailAccount emAccount;

    if (useAutodiscover) {
      try {
        final config = await em.Discover.discover(account.email);
        if (config != null) {
          final discovered = em.MailAccount.fromDiscoveredSettings(
            name: 'EAS Mail',
            email: account.email,
            password: account.password,
            config: config,
            userName: account.loginUsername,
          );

          // Autodiscover can return an incorrect SocketType for the SMTP port
          // (e.g. SSL instead of STARTTLS for port 587), causing a 20-second
          // TCP/SSL handshake timeout.  Rebuild the account using:
          //   • IMAP settings from autodiscover (host/port/socketType)
          //   • SMTP host/port from the account's saved settings if available,
          //     otherwise from autodiscover
          //   • SMTP SocketType always derived from the port via _socketType()
          final outHost = account.smtpHost.isNotEmpty
              ? account.smtpHost
              : discovered.outgoing.serverConfig.hostname;
          final outPort = (account.smtpHost.isNotEmpty && account.smtpPort > 0)
              ? account.smtpPort
              : discovered.outgoing.serverConfig.port;

          emAccount = em.MailAccount.fromManualSettings(
            name: 'EAS Mail',
            email: account.email,
            userName: account.loginUsername,
            password: account.password,
            incomingHost: discovered.incoming.serverConfig.hostname,
            outgoingHost: outHost,
            incomingPort: discovered.incoming.serverConfig.port,
            outgoingPort: outPort,
            incomingSocketType: discovered.incoming.serverConfig.socketType,
            outgoingSocketType: _socketType(account.smtpSsl, outPort, incoming: false),
            loginName: account.loginUsername,
          );
        } else {
          emAccount = _manualAccount(account);
        }
      } catch (_) {
        emAccount = _manualAccount(account);
      }
    } else {
      emAccount = _manualAccount(account);
    }

    // Remember the resolved host/port so MailSession can persist them.
    resolvedImapHost = emAccount.incoming.serverConfig.hostname;
    resolvedImapPort = emAccount.incoming.serverConfig.port;
    resolvedSmtpHost = emAccount.outgoing.serverConfig.hostname;
    resolvedSmtpPort = emAccount.outgoing.serverConfig.port;

    _client = em.MailClient(emAccount, isLogEnabled: false);
    await _client!.connect();
    await _client!.selectInbox();
  }

  em.MailAccount _manualAccount(MailAccount account) {
    if (account.imapHost.isEmpty || account.smtpHost.isEmpty) {
      throw const MailException('Укажите IMAP и SMTP серверы');
    }
    return em.MailAccount.fromManualSettings(
      name: 'EAS Mail',
      email: account.email,
      userName: account.loginUsername,
      password: account.password,
      incomingHost: account.imapHost,
      outgoingHost: account.smtpHost,
      incomingPort: account.imapPort,
      outgoingPort: account.smtpPort,
      incomingSocketType: _socketType(
        account.imapSsl,
        account.imapPort,
        incoming: true,
      ),
      outgoingSocketType: _socketType(
        account.smtpSsl,
        account.smtpPort,
        incoming: false,
      ),
      loginName: account.loginUsername,
    );
  }

  em.SocketType _socketType(bool ssl, int port, {required bool incoming}) {
    if (incoming) {
      // IMAP: 993 = SSL/TLS, 143 = STARTTLS or plain
      if (port == 993) return em.SocketType.ssl;
      if (port == 143) return ssl ? em.SocketType.starttls : em.SocketType.plain;
    } else {
      // SMTP: 465 = SSL/TLS (implicit),
      //       587 = STARTTLS (explicit, even if user ticked "SSL"),
      //        25 = plain / STARTTLS
      if (port == 465) return em.SocketType.ssl;
      if (port == 587) return em.SocketType.starttls;
      if (port == 25) return ssl ? em.SocketType.starttls : em.SocketType.plain;
    }
    // Non-standard port: trust the user's ssl toggle.
    return ssl ? em.SocketType.ssl : em.SocketType.plain;
  }

  // ── Fetch inbox / folder (envelope-only, paged) ──────────────────────────

  @override
  Future<List<MailMessage>> fetchInbox({int limit = 0, int page = 1}) async {
    final client = _client!;
    await client.selectInbox();
    final messages = await client.fetchMessages(
      count: _batchSize,
      page: page,
      fetchPreference: em.FetchPreference.envelope,
    );
    return _convertMessages(messages, 'INBOX', bodyLoaded: false);
  }

  @override
  Future<List<MailFolder>> fetchFolders() async {
    final mailboxes = await _client!.listMailboxes();
    _mailboxes = mailboxes;
    return mailboxes.map(_toMailFolder).toList();
  }

  @override
  Future<List<MailMessage>> fetchFolder(
    String folderId, {
    int limit = 0,
    int page = 1,
  }) async {
    final client = _client!;
    await _selectMailboxForFolder(folderId);
    final messages = await client.fetchMessages(
      count: _batchSize,
      page: page,
      fetchPreference: em.FetchPreference.envelope,
    );
    return _convertMessages(messages, folderId, bodyLoaded: false);
  }

  // ── Lazy body loading ────────────────────────────────────────────────────

  @override
  Future<MailMessage> loadMessageBody(MailMessage message) async {
    final mimeMsg = _msgCache[message.serverId];
    if (mimeMsg == null) return message;
    try {
      await _selectMailboxForFolder(message.collectionId);
      final fullMsg = await _client!.fetchMessageContents(mimeMsg);
      _msgCache[message.serverId] = fullMsg;

      final htmlPart = fullMsg.decodeTextHtmlPart();
      var body = fullMsg.decodeTextPlainPart();
      String? bodyHtml;
      if (htmlPart != null && htmlPart.trim().isNotEmpty) {
        bodyHtml = htmlPart;
        body ??= htmlPart.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
      }

      final attachments = <MailAttachment>[];
      for (final info in fullMsg.findContentInfo(
        disposition: em.ContentDisposition.attachment,
      )) {
        final name = _safeFileName(info.fileName);
        attachments.add(MailAttachment(
          displayName: name,
          fileReference: 'imap:${message.serverId}:${info.fetchId}',
          size: info.size,
        ));
      }

      return message.copyWith(
        body: body,
        bodyHtml: bodyHtml,
        bodyLoaded: true,
        attachments: attachments,
      );
    } catch (_) {
      return message; // keep bodyLoaded=false, caller can retry
    }
  }

  // ── Mark as read ─────────────────────────────────────────────────────────

  @override
  Future<void> markAsRead(MailMessage message) async {
    final emMsg = _msgCache[message.serverId];
    if (emMsg == null) return;
    try {
      await _client!.flagMessage(emMsg, isSeen: true);
    } catch (_) {}
  }

  // ── Delete message ────────────────────────────────────────────────────────

  @override
  Future<void> deleteMessage(MailMessage message) async {
    final emMsg = _msgCache[message.serverId];
    if (emMsg == null) return;
    try {
      await _selectMailboxForFolder(message.collectionId);
      await _client!.deleteMessage(emMsg);
      _msgCache.remove(message.serverId);
    } catch (_) {}
  }

  // ── Send mail ────────────────────────────────────────────────────────────

  @override
  Future<void> sendMail({
    required MailAccount account,
    required String to,
    required String subject,
    required String body,
    List<MimeAttachment>? attachments,
    bool isHtml = false,
  }) async {
    final builder = em.MessageBuilder()
      ..from = [em.MailAddress('', account.email)]
      ..to = [em.MailAddress.parse(to)]
      ..subject = subject;

    if (isHtml) {
      final plain = body
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      builder.addTextPlain(plain);
      builder.addTextHtml(body);
    } else {
      builder.addTextPlain(body);
    }

    if (attachments != null) {
      for (final att in attachments) {
        builder.addBinary(
          att.bytes,
          em.MediaType.fromText('application/octet-stream'),
          filename: att.filename,
        );
      }
    }

    // Use a dedicated SmtpClient so we can:
    //   • use the current account settings (not the cached autodiscover result)
    //   • apply a shorter per-attempt timeout (10 s)
    //   • automatically fall back to the alternative SMTP port on failure
    final mimeMsg = builder.buildMimeMessage();
    await _sendViaDedicatedSmtp(account, mimeMsg);

    // Optionally copy to Sent folder; failures are silently ignored.
    _appendToSent(mimeMsg);
  }

  /// Connects a fresh [SmtpClient] and sends [mimeMsg].
  ///
  /// Prefers [account.smtpHost/Port] when set; falls back to the host/port
  /// resolved during [connect].  Tries the primary port first (10-second
  /// timeout), then automatically retries on the alternative port
  /// (587 ↔ 465) if the first attempt times out or the TCP connection fails.
  Future<void> _sendViaDedicatedSmtp(
    MailAccount account,
    em.MimeMessage mimeMsg,
  ) async {
    final host = account.smtpHost.isNotEmpty
        ? account.smtpHost
        : (resolvedSmtpHost ?? '');
    if (host.isEmpty) {
      throw const MailException(
        'SMTP сервер не настроен. '
        'Откройте настройки аккаунта и укажите адрес SMTP сервера.',
      );
    }

    final basePort = (account.smtpHost.isNotEmpty && account.smtpPort > 0)
        ? account.smtpPort
        : (resolvedSmtpPort ?? 587);

    // Build an ordered list of (port, socketType) to try.
    // Primary: whatever is configured. Fallback: the other common SMTP port.
    final candidates = <(int, em.SocketType)>[
      (basePort, _socketType(account.smtpSsl, basePort, incoming: false)),
    ];
    final altPort = basePort == 587 ? 465 : (basePort == 465 ? 587 : null);
    if (altPort != null) {
      candidates.add(
        (altPort, _socketType(account.smtpSsl, altPort, incoming: false)),
      );
    }

    Object? lastError;
    for (final (port, socketType) in candidates) {
      final smtp = em.SmtpClient('easmail.local', isLogEnabled: false);
      try {
        final isSecure = socketType == em.SocketType.ssl;
        await smtp.connectToServer(
          host,
          port,
          isSecure: isSecure,
          timeout: const Duration(seconds: 10),
        );
        await smtp.ehlo();
        if (!isSecure && smtp.serverInfo.supportsStartTls) {
          await smtp.startTls();
          await smtp.ehlo(); // re-issue EHLO after TLS upgrade
        }
        await smtp.authenticate(account.loginUsername, account.password);
        await smtp.sendMessage(mimeMsg);
        return; // ← sent successfully
      } on TimeoutException {
        // Port unreachable — try the next candidate.
        lastError = MailException(
          'Нет ответа от SMTP $host:$port (таймаут 10 с)',
        );
      } on SocketException catch (e) {
        // TCP-level failure — try the next candidate.
        lastError = MailException(
          'Нет соединения с SMTP $host:$port: ${e.message}',
        );
      } on em.SmtpException catch (e) {
        // Auth / protocol error — don't retry different ports.
        throw MailException('SMTP ошибка ($host:$port): $e');
      } catch (e) {
        // Unknown error — surface immediately.
        rethrow;
      } finally {
        try {
          await smtp.disconnect();
        } catch (_) {}
      }
    }
    if (lastError is MailException) throw lastError;
    throw MailException('Не удалось отправить письмо: $lastError');
  }

  void _appendToSent(em.MimeMessage mimeMsg) {
    final sent = _mailboxes
        .where((mb) => mb.flags.contains(em.MailboxFlag.sent))
        .firstOrNull;
    if (sent == null) return;
    Future(() async {
      try {
        await _client!.appendMessage(
          mimeMsg,
          sent,
          flags: [em.MessageFlags.seen],
        );
      } catch (_) {
        // Silently ignore: the message was already sent via SMTP.
        // Some servers auto-save to Sent; others don't support APPEND.
      }
    });
  }

  // ── Attachments ──────────────────────────────────────────────────────────

  @override
  Future<Uint8List> loadAttachmentBytes({
    required MailMessage message,
    required int attachmentIndex,
  }) async {
    final path = await downloadAttachment(
      message: message,
      attachmentIndex: attachmentIndex,
    );
    return File(path).readAsBytes();
  }

  @override
  Future<String> downloadAttachment({
    required MailMessage message,
    required int attachmentIndex,
  }) async {
    if (attachmentIndex < 0 || attachmentIndex >= message.attachments.length) {
      throw const MailException('Вложение не найдено');
    }

    final ref = message.attachments[attachmentIndex].fileReference;
    final match = RegExp(r'^imap:(\d+):(.+)$').firstMatch(ref);
    if (match == null) {
      throw const MailException('Некорректная ссылка на вложение');
    }

    final uidStr = match.group(1)!;
    final fetchId = match.group(2)!;

    var mimeMsg = _msgCache[uidStr];
    if (mimeMsg == null) {
      throw const MailException('Письмо не найдено в кэше');
    }

    // Ensure we have the full message content (not just envelope) before
    // fetching the attachment part.
    if (mimeMsg.body == null) {
      await _selectMailboxForFolder(message.collectionId);
      mimeMsg = await _client!.fetchMessageContents(mimeMsg);
      _msgCache[uidStr] = mimeMsg;
    }

    final part = await _client!.fetchMessagePart(mimeMsg, fetchId);
    final bytes = part.decodeContentBinary();
    if (bytes == null || bytes.isEmpty) {
      throw const MailException('Не удалось прочитать вложение');
    }

    final dir = await getApplicationDocumentsDirectory();
    final name = message.attachments[attachmentIndex].displayName;
    final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File(p.join(dir.path, safeName));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ── Disconnect ───────────────────────────────────────────────────────────

  @override
  Future<void> disconnect() async {
    try {
      await _client?.disconnect();
    } catch (_) {}
    _client = null;
    _msgCache.clear();
    _mailboxes.clear();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Future<void> _selectMailboxForFolder(String folderId) async {
    if (folderId == 'INBOX') {
      await _client!.selectInbox();
      return;
    }
    for (final mb in _mailboxes) {
      if (mb.path == folderId || mb.encodedName == folderId) {
        await _client!.selectMailbox(mb);
        return;
      }
    }
    // Fallback
    await _client!.selectInbox();
  }

  List<MailMessage> _convertMessages(
    List<em.MimeMessage> messages,
    String collectionId, {
    bool bodyLoaded = true,
  }) {
    final result = <MailMessage>[];
    for (final msg in messages) {
      final uid = msg.uid;
      if (uid == null) continue;

      _msgCache[uid.toString()] = msg;

      String? body;
      String? bodyHtml;
      List<MailAttachment> attachments = const [];

      if (bodyLoaded) {
        final htmlPart = msg.decodeTextHtmlPart();
        body = msg.decodeTextPlainPart();
        if (htmlPart != null && htmlPart.trim().isNotEmpty) {
          bodyHtml = htmlPart;
          body ??= htmlPart.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
        }

        attachments = [];
        for (final info in msg.findContentInfo(
          disposition: em.ContentDisposition.attachment,
        )) {
          final name = _safeFileName(info.fileName);
          attachments.add(MailAttachment(
            displayName: name,
            fileReference: 'imap:$uid:${info.fetchId}',
            size: info.size,
          ));
        }
      }

      result.add(MailMessage(
        serverId: uid.toString(),
        collectionId: collectionId,
        subject: _safeSubject(msg),
        from: msg.from?.isNotEmpty == true
            ? _formatAddress(msg.from!.first)
            : '',
        to: msg.to
            ?.map((a) => a.email)
            .where((e) => e.isNotEmpty)
            .join(', '),
        body: body,
        bodyHtml: bodyHtml,
        read: msg.isSeen,
        dateReceived: msg.decodeDate(),
        attachments: attachments,
        bodyLoaded: bodyLoaded,
      ));
    }
    return result;
  }

  String _formatAddress(em.MailAddress addr) {
    // personalName may be null or a raw MIME encoded-word when the server
    // sends malformed Base64 (e.g. triple-padding "==="). Treat any string
    // that still looks like an encoded word as absent.
    String? name;
    try {
      name = addr.personalName?.trim();
      if (name != null && _isMimeEncodedWord(name)) name = null;
    } catch (_) {
      name = null;
    }

    final email = addr.email.trim();
    if (name != null && name.isNotEmpty && name != email) {
      return '$name <$email>';
    }
    return email.isNotEmpty ? email : addr.toString();
  }

  /// Returns true when [s] is an undecoded MIME encoded-word, e.g.
  /// `=?windows-1251?B?...?=`.  enough_mail emits a warning and may
  /// leave the raw token in personalName when Base64 is malformed.
  bool _isMimeEncodedWord(String s) =>
      s.startsWith('=?') && s.contains('?=');

  /// Returns a safe display name for an attachment, filtering out undecoded
  /// MIME encoded-words that appear when enough_mail can't decode the charset.
  String _safeFileName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'attachment';
    final s = raw.trim();
    if (_isMimeEncodedWord(s)) return 'attachment';
    return s;
  }

  /// Safely decodes the subject, returning a placeholder on any error or
  /// when the value is an undecoded MIME encoded-word.
  String _safeSubject(em.MimeMessage msg) {
    try {
      final s = msg.decodeSubject();
      if (s == null || s.trim().isEmpty) return '(без темы)';
      if (_isMimeEncodedWord(s.trim())) return '(без темы)';
      return s;
    } catch (_) {
      return '(без темы)';
    }
  }

  MailFolder _toMailFolder(em.Mailbox mb) {
    MailFolderType type = MailFolderType.other;
    if (mb.isInbox) {
      type = MailFolderType.inbox;
    } else {
      final flags = mb.flags;
      if (flags.contains(em.MailboxFlag.sent)) {
        type = MailFolderType.sent;
      } else if (flags.contains(em.MailboxFlag.trash)) {
        type = MailFolderType.trash;
      } else if (flags.contains(em.MailboxFlag.drafts)) {
        type = MailFolderType.drafts;
      } else if (flags.contains(em.MailboxFlag.junk)) {
        type = MailFolderType.spam;
      }
    }
    return MailFolder(id: mb.path, name: mb.name, type: type);
  }
}
