import 'dart:typed_data';

import '../eas/mime_builder.dart';
import '../models/mail_folder.dart';
import 'models/mail_account.dart';
import 'models/mail_message.dart';

/// Абстракция почтового бэкенда (EAS или IMAP/SMTP).
abstract class MailBackend {
  Future<void> connect(MailAccount account, {bool useAutodiscover = true});

  /// Fetch the most recent messages from Inbox.
  Future<List<MailMessage>> fetchInbox({int limit = 0, int page = 1});

  Future<List<MailFolder>> fetchFolders();

  /// Fetch messages from a folder.
  /// [page] = 1 → newest batch, [page] = 2 → next older batch, etc.
  Future<List<MailMessage>> fetchFolder(
    String folderId, {
    int limit = 0,
    int page = 1,
  });

  Future<void> markAsRead(MailMessage message);

  /// Delete [message] from the server.
  Future<void> deleteMessage(MailMessage message);

  Future<void> sendMail({
    required MailAccount account,
    required String to,
    required String subject,
    required String body,
    List<MimeAttachment>? attachments,
    bool isHtml = false,
  });

  Future<Uint8List> loadAttachmentBytes({
    required MailMessage message,
    required int attachmentIndex,
  });

  /// Returns path to saved file.
  Future<String> downloadAttachment({
    required MailMessage message,
    required int attachmentIndex,
  });

  /// Load the full body of an envelope-only [message].
  /// Returns the updated message with [MailMessage.bodyLoaded] = true.
  /// Returns [message] unchanged if the body cannot be loaded.
  Future<MailMessage> loadMessageBody(MailMessage message);

  Future<void> disconnect();
}
