import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../eas/autodiscover.dart';
import '../../eas/eas_client.dart';
import '../../eas/mime_builder.dart';
import '../../eas/models/eas_folder.dart';
import '../../models/mail_folder.dart';
import '../mail_exception.dart';
import '../mail_backend.dart';
import '../models/mail_account.dart';
import '../models/mail_message.dart';

class EasMailBackend implements MailBackend {
  EasClient? _client;
  String? lastServerUrl;

  @override
  Future<void> connect(MailAccount account, {bool useAutodiscover = true}) async {
    var serverUrl = account.activeSyncUrl;
    if (useAutodiscover && !account.usesOAuth) {
      final discovered = await EasAutodiscover.discoverActiveSyncUrl(
        email: account.email,
        password: account.password,
        domain: account.domain,
      );
      if (discovered != null) serverUrl = discovered;
    } else if (useAutodiscover && account.usesOAuth && account.accessToken != null) {
      final discovered = await EasAutodiscover.discoverActiveSyncUrl(
        email: account.email,
        bearerToken: account.accessToken,
      );
      if (discovered != null) serverUrl = discovered;
    }

    _client = EasClient(
      serverUrl: serverUrl,
      email: account.email,
      password: account.password,
      domain: account.domain,
      accessToken: account.accessToken,
    );
    await _client!.connect();
    lastServerUrl = _client!.serverUrl;
  }

  @override
  Future<List<MailMessage>> fetchInbox({int limit = 0, int page = 1}) async {
    // EAS uses SyncKey-based incremental sync — pagination is not applicable.
    if (page > 1) return const [];
    return _client!.syncInbox();
  }

  @override
  Future<List<MailFolder>> fetchFolders() async {
    final easFolders = _client!.cachedFolders;
    return easFolders.map((f) => _toMailFolder(f)).toList();
  }

  @override
  Future<List<MailMessage>> fetchFolder(
    String folderId, {
    int limit = 0,
    int page = 1,
  }) async {
    // EAS uses SyncKey-based incremental sync — pagination is not applicable.
    if (page > 1) return const [];
    return _client!.syncInbox(collectionId: folderId);
  }

  @override
  Future<MailMessage> loadMessageBody(MailMessage message) async {
    // EAS messages always include the full body — nothing to load.
    return message;
  }

  @override
  Future<void> markAsRead(MailMessage message) async {
    await _client!.markAsRead(message.collectionId, message.serverId);
  }

  @override
  Future<void> deleteMessage(MailMessage message) async {
    await _client!.deleteItem(message.collectionId, message.serverId);
  }

  MailFolder _toMailFolder(EasFolder f) {
    return MailFolder(
      id: f.serverId,
      name: f.displayName,
      parentId: f.parentId,
      type: _easTypeToFolderType(f.type),
    );
  }

  MailFolderType _easTypeToFolderType(int type) {
    switch (type) {
      case 2:
        return MailFolderType.inbox;
      case 3:
        return MailFolderType.drafts;
      case 4:
        return MailFolderType.trash;
      case 5:
        return MailFolderType.sent;
      default:
        return MailFolderType.other;
    }
  }

  @override
  Future<void> sendMail({
    required MailAccount account,
    required String to,
    required String subject,
    required String body,
    List<MimeAttachment>? attachments,
    bool isHtml = false,
  }) async {
    await _client!.sendMail(
      to: to,
      subject: subject,
      body: body,
      attachments: attachments,
      isHtml: isHtml,
    );
  }

  @override
  Future<Uint8List> loadAttachmentBytes({
    required MailMessage message,
    required int attachmentIndex,
  }) async {
    if (attachmentIndex < 0 || attachmentIndex >= message.attachments.length) {
      throw const MailException('Вложение не найдено');
    }
    final att = message.attachments[attachmentIndex];
    return _client!.fetchAttachment(att.fileReference);
  }

  @override
  Future<String> downloadAttachment({
    required MailMessage message,
    required int attachmentIndex,
  }) async {
    if (attachmentIndex < 0 || attachmentIndex >= message.attachments.length) {
      throw const MailException('Вложение не найдено');
    }
    final att = message.attachments[attachmentIndex];
    final bytes = await _client!.fetchAttachment(att.fileReference);

    final dir = await getApplicationDocumentsDirectory();
    final safeName = att.displayName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File(p.join(dir.path, safeName));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Future<void> disconnect() async {
    _client = null;
  }
}
