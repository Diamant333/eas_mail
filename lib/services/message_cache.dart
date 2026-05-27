import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../mail/models/mail_attachment.dart';
import '../mail/models/mail_message.dart';

/// Persists message envelopes (headers, no body) to disk per account/folder.
/// On app startup cached envelopes are shown instantly while the server
/// connection loads new/updated messages in the background.
class MessageCacheService {
  static const int _version = 2;

  Future<Directory> _dir(String accountEmail) async {
    final base = await getApplicationDocumentsDirectory();
    final safe = accountEmail.replaceAll(RegExp(r'[<>:"/\\|?*@\s]'), '_');
    final dir =
        Directory(p.join(base.path, 'mail_cache_v$_version', safe));
    await dir.create(recursive: true);
    return dir;
  }

  File _file(Directory dir, String folderId) {
    final safe = folderId.replaceAll(RegExp(r'[<>:"/\\|?*\s]'), '_');
    return File(p.join(dir.path, '$safe.json'));
  }

  // ── Public API ───────────────────────────────────────────────────────────

  Future<List<MailMessage>> load(
      String accountEmail, String folderId) async {
    if (kIsWeb) return [];
    try {
      final dir = await _dir(accountEmail);
      final file = _file(dir, folderId);
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      final list = jsonDecode(text) as List;
      return list
          .map((e) => _fromJson(e as Map<String, dynamic>, folderId))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(
      String accountEmail, String folderId, List<MailMessage> messages) async {
    if (kIsWeb) return;
    try {
      final dir = await _dir(accountEmail);
      final file = _file(dir, folderId);
      // Cap cache at 500 messages to bound file size.
      final toStore =
          messages.length > 500 ? messages.sublist(0, 500) : messages;
      await file.writeAsString(jsonEncode(toStore.map(_toJson).toList()));
    } catch (_) {}
  }

  Future<void> clear(String accountEmail) async {
    if (kIsWeb) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      final safe = accountEmail.replaceAll(RegExp(r'[<>:"/\\|?*@\s]'), '_');
      final dir =
          Directory(p.join(base.path, 'mail_cache_v$_version', safe));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> _toJson(MailMessage m) => {
        'id': m.serverId,
        's': m.subject,
        'f': m.from,
        't': m.to,
        'd': m.dateReceived?.millisecondsSinceEpoch,
        'r': m.read,
        'ha': m.hasAttachments,
      };

  MailMessage _fromJson(Map<String, dynamic> j, String folderId) {
    final hasAtts = j['ha'] as bool? ?? false;
    return MailMessage(
      serverId: j['id'] as String,
      collectionId: folderId,
      subject: j['s'] as String? ?? '',
      from: j['f'] as String? ?? '',
      to: j['t'] as String?,
      read: j['r'] as bool? ?? false,
      dateReceived: j['d'] != null
          ? DateTime.fromMillisecondsSinceEpoch(j['d'] as int)
          : null,
      // Placeholder attachment so that hasAttachments == true in list view.
      attachments: hasAtts
          ? const [MailAttachment(displayName: '', fileReference: '')]
          : const [],
      bodyLoaded: false,
    );
  }
}
