import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'mime_builder.dart';
import 'models/eas_attachment.dart';
import '../mail/models/mail_attachment.dart';
import '../mail/models/mail_message.dart';
import 'models/eas_folder.dart';
import 'wbxml/code_pages.dart';
import 'wbxml/wbxml_codec.dart';
import 'wbxml/wbxml_node.dart';

/// Клиент Exchange ActiveSync (EAS 16.1).
class EasClient {
  EasClient({
    required String serverUrl,
    required this.email,
    this.password = '',
    this.domain,
    this.accessToken,
    String? deviceId,
    this.deviceType = 'EASMail',
    this.protocolVersion = '16.1',
  })  : deviceId = deviceId ?? const Uuid().v4().replaceAll('-', '').substring(0, 16),
        _baseUrl = _normalizeUrl(serverUrl);

  final String _baseUrl;

  String get serverUrl => _baseUrl;
  final String email;
  final String password;
  final String? domain;
  final String? accessToken;
  final String deviceId;
  final String deviceType;
  final String protocolVersion;

  String policyKey = '0';
  String folderSyncKey = '0';
  String? inboxCollectionId;
  final Map<String, String> collectionSyncKeys = {};
  final List<EasFolder> _cachedFolders = [];

  bool get usesBearer => accessToken != null && accessToken!.isNotEmpty;

  String get _username {
    if (domain != null && domain!.isNotEmpty && !email.contains('\\')) {
      return '$domain\\$email';
    }
    return email;
  }

  static String _normalizeUrl(String url) {
    var base = url.trim();
    if (!base.startsWith('http')) base = 'https://$base';
    base = base.replaceAll(RegExp(r'/+$'), '');
    if (!base.toLowerCase().contains('microsoft-server-activesync')) {
      base = '$base/Microsoft-Server-ActiveSync';
    }
    return base;
  }

  List<EasFolder> get cachedFolders => _cachedFolders;

  Future<void> connect() async {
    await provision();
    final folders = await folderSync();
    _cachedFolders
      ..clear()
      ..addAll(folders);
    inboxCollectionId ??= await _findInboxId();
  }

  Future<void> provision() async {
    var request = _provisionInitial();
    for (var step = 0; step < 3; step++) {
      final response = await _command('Provision', request);
      final root = WbXmlCodec.decode(response);
      final status = int.tryParse(root.childText('Status') ?? '') ?? -1;
      if (status != 1 && status != 2) {
        throw EasException('Provision отклонён (Status=$status)');
      }

      final policy = root.child('Policies')?.child('Policy');
      final key = policy?.childText('PolicyKey');
      if (key != null && key.isNotEmpty) policyKey = key;

      final policyStatus = int.tryParse(policy?.childText('Status') ?? '') ?? 1;
      if (policyStatus == 1 && key != null) {
        request = _provisionAcknowledge(key);
        continue;
      }
      break;
    }
  }

  Future<List<EasFolder>> folderSync() async {
    final request = WbXmlCodec.encode(
      WbXmlCodec.element(
        EasCodePages.folderHierarchy,
        'FolderSync',
        children: [
          WbXmlCodec.element(
            EasCodePages.folderHierarchy,
            'SyncKey',
            text: folderSyncKey,
          ),
        ],
      ),
    );

    final response = await _command('FolderSync', request);
    final root = WbXmlCodec.decode(response);
    final status = int.tryParse(root.childText('Status') ?? '') ?? -1;
    if (status != 1) {
      throw EasException('FolderSync ошибка (Status=$status)');
    }

    final newKey = root.childText('SyncKey');
    if (newKey != null) folderSyncKey = newKey;

    final folders = <EasFolder>[];
    final changes = root.child('Changes');
    if (changes != null) {
      for (final add in changes.childrenNamed('Add')) {
        final folder = EasFolder(
          serverId: add.childText('ServerId') ?? '',
          displayName: add.childText('DisplayName') ?? '',
          type: int.tryParse(add.childText('Type') ?? '0') ?? 0,
          parentId: add.childText('ParentId'),
        );
        folders.add(folder);
        if (folder.isInbox) inboxCollectionId = folder.serverId;
      }
    }
    return folders;
  }

  Future<List<MailMessage>> syncInbox({String? collectionId}) async {
    final inboxId = collectionId ?? inboxCollectionId ?? await _findInboxId();
    inboxCollectionId = inboxId;

    // Reset to full sync if not yet initialised.
    if (!collectionSyncKeys.containsKey(inboxId)) {
      collectionSyncKeys[inboxId] = '0';
    }

    final messages = <MailMessage>[];
    bool moreAvailable = true;
    int status3Retries = 0;
    const batchSize = 256;

    while (moreAvailable) {
      final syncKey = collectionSyncKeys[inboxId]!;
      final request = WbXmlCodec.encode(
        WbXmlCodec.element(
          EasCodePages.airSync,
          'Sync',
          children: [
            WbXmlCodec.element(
              EasCodePages.airSync,
              'Collections',
              children: [
                WbXmlCodec.element(
                  EasCodePages.airSync,
                  'Collection',
                  children: [
                    WbXmlCodec.element(EasCodePages.airSync, 'SyncKey', text: syncKey),
                    WbXmlCodec.element(EasCodePages.airSync, 'CollectionId', text: inboxId),
                    WbXmlCodec.element(EasCodePages.airSync, 'GetChanges', text: '1'),
                    WbXmlCodec.element(EasCodePages.airSync, 'WindowSize', text: '$batchSize'),
                    WbXmlCodec.element(
                      EasCodePages.airSync,
                      'Options',
                      children: [
                        WbXmlCodec.element(EasCodePages.airSync, 'MIMESupport', text: '0'),
                        WbXmlCodec.element(EasCodePages.airSync, 'MIMETruncation', text: '5'),
                        WbXmlCodec.element(
                          EasCodePages.airSyncBase,
                          'BodyPreference',
                          children: [
                            WbXmlCodec.element(EasCodePages.airSyncBase, 'Type', text: '2'),
                            WbXmlCodec.element(
                                EasCodePages.airSyncBase, 'TruncationSize', text: '65536'),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final response = await _command('Sync', request);
      final root = WbXmlCodec.decode(response);
      final collection = root.child('Collections')?.child('Collection');
      if (collection == null) break;

      final collStatus = int.tryParse(collection.childText('Status') ?? '') ?? -1;
      if (collStatus == 3) {
        // Invalid SyncKey — reset once, then give up to avoid infinite loop.
        if (status3Retries++ >= 1) {
          throw const EasException('Sync: не удалось сбросить SyncKey');
        }
        collectionSyncKeys[inboxId] = '0';
        messages.clear();
        continue;
      }
      if (collStatus != 1) {
        throw EasException('Sync ошибка (Status=$collStatus)');
      }

      final newKey = collection.childText('SyncKey');
      if (newKey != null) collectionSyncKeys[inboxId] = newKey;

      for (final add
          in collection.child('Commands')?.childrenNamed('Add') ?? <WbXmlNode>[]) {
        final serverId = add.childText('ServerId') ?? '';
        final appData = add.child('ApplicationData');
        if (appData == null) continue;
        messages.add(_parseMessage(serverId, inboxId, appData));
      }

      // MoreAvailable is a flag element (no text content) — use child(), not childText().
      moreAvailable = collection.child('MoreAvailable') != null;
    }

    return messages;
  }

  /// Отправка письма (команда SendMail).
  Future<void> sendMail({
    required String to,
    required String subject,
    required String body,
    List<MimeAttachment>? attachments,
    bool saveInSent = true,
    bool isHtml = false,
  }) async {
    final mime = isHtml
        ? MimeBuilder.buildHtml(
            from: email,
            to: to,
            subject: subject,
            htmlBody: body,
            attachments: attachments,
          )
        : MimeBuilder.build(
            from: email,
            to: to,
            subject: subject,
            body: body,
            attachments: attachments,
          );

    final clientId = const Uuid().v4();
    final request = WbXmlCodec.encode(
      WbXmlCodec.element(
        EasCodePages.composeMail,
        'SendMail',
        children: [
          WbXmlCodec.element(EasCodePages.composeMail, 'ClientId', text: clientId),
          if (saveInSent)
            WbXmlCodec.element(EasCodePages.composeMail, 'SaveInSentItems', text: '1'),
          WbXmlCodec.element(EasCodePages.composeMail, 'MIME', text: mime),
        ],
      ),
    );

    final response = await _command('SendMail', request);
    final root = WbXmlCodec.decode(response);
    final status = int.tryParse(root.childText('Status') ?? '') ?? -1;
    if (status != 1) {
      throw EasException('SendMail ошибка (Status=$status)');
    }
  }

  /// Отметить письмо как прочитанное.
  Future<void> markAsRead(String collectionId, String serverId) async {
    final syncKey = collectionSyncKeys[collectionId];
    if (syncKey == null || syncKey == '0') return;

    final request = WbXmlCodec.encode(
      WbXmlCodec.element(EasCodePages.airSync, 'Sync', children: [
        WbXmlCodec.element(EasCodePages.airSync, 'Collections', children: [
          WbXmlCodec.element(EasCodePages.airSync, 'Collection', children: [
            WbXmlCodec.element(EasCodePages.airSync, 'SyncKey', text: syncKey),
            WbXmlCodec.element(EasCodePages.airSync, 'CollectionId', text: collectionId),
            WbXmlCodec.element(EasCodePages.airSync, 'Commands', children: [
              WbXmlCodec.element(EasCodePages.airSync, 'Change', children: [
                WbXmlCodec.element(EasCodePages.airSync, 'ServerId', text: serverId),
                WbXmlCodec.element(EasCodePages.airSync, 'ApplicationData', children: [
                  WbXmlCodec.element(EasCodePages.email, 'Read', text: '1'),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]),
    );

    try {
      final response = await _command('Sync', request);
      final root = WbXmlCodec.decode(response);
      final collection = root.child('Collections')?.child('Collection');
      final newKey = collection?.childText('SyncKey');
      if (newKey != null && newKey.isNotEmpty) {
        collectionSyncKeys[collectionId] = newKey;
      }
    } catch (_) {
      // Silently ignore mark-as-read errors
    }
  }

  /// Удалить письмо с сервера.
  Future<void> deleteItem(String collectionId, String serverId) async {
    final syncKey = collectionSyncKeys[collectionId];
    if (syncKey == null || syncKey == '0') return;

    final request = WbXmlCodec.encode(
      WbXmlCodec.element(EasCodePages.airSync, 'Sync', children: [
        WbXmlCodec.element(EasCodePages.airSync, 'Collections', children: [
          WbXmlCodec.element(EasCodePages.airSync, 'Collection', children: [
            WbXmlCodec.element(EasCodePages.airSync, 'SyncKey', text: syncKey),
            WbXmlCodec.element(
                EasCodePages.airSync, 'CollectionId', text: collectionId),
            WbXmlCodec.element(EasCodePages.airSync, 'Commands', children: [
              WbXmlCodec.element(EasCodePages.airSync, 'Delete', children: [
                WbXmlCodec.element(
                    EasCodePages.airSync, 'ServerId', text: serverId),
              ]),
            ]),
          ]),
        ]),
      ]),
    );

    try {
      final response = await _command('Sync', request);
      final root = WbXmlCodec.decode(response);
      final collection = root.child('Collections')?.child('Collection');
      final newKey = collection?.childText('SyncKey');
      if (newKey != null && newKey.isNotEmpty) {
        collectionSyncKeys[collectionId] = newKey;
      }
    } catch (_) {
      // Silently ignore delete errors
    }
  }

  /// Загрузка вложения по FileReference (ItemOperations).
  Future<Uint8List> fetchAttachment(String fileReference) async {
    final request = WbXmlCodec.encode(
      WbXmlCodec.element(
        EasCodePages.itemOperations,
        'ItemOperations',
        children: [
          WbXmlCodec.element(
            EasCodePages.itemOperations,
            'Fetch',
            children: [
              WbXmlCodec.element(EasCodePages.itemOperations, 'Store', text: '1'),
              WbXmlCodec.element(
                EasCodePages.airSyncBase,
                'FileReference',
                text: fileReference,
              ),
              WbXmlCodec.element(
                EasCodePages.itemOperations,
                'Options',
                children: [
                  WbXmlCodec.element(EasCodePages.itemOperations, 'Range', text: '0-5242880'),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final response = await _command('ItemOperations', request);
    final root = WbXmlCodec.decode(response);
    final fetch = root.child('Response')?.child('Fetch');
    final status = int.tryParse(fetch?.childText('Status') ?? '') ?? -1;
    if (status != 1) {
      throw EasException('Не удалось загрузить вложение (Status=$status)');
    }

    final data = fetch?.child('Properties')?.childText('Data');
    if (data == null || data.isEmpty) {
      throw const EasException('Пустой ответ вложения');
    }

    try {
      return base64Decode(data.replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      return Uint8List.fromList(utf8.encode(data));
    }
  }

  Future<String> _findInboxId() async {
    final folders = await folderSync();
    final inbox = folders.where((f) => f.isInbox).toList();
    if (inbox.isEmpty) {
      throw const EasException('Папка «Входящие» не найдена');
    }
    inboxCollectionId = inbox.first.serverId;
    return inbox.first.serverId;
  }

  MailMessage _parseMessage(String serverId, String collectionId, WbXmlNode appData) {
    final subject = appData.childText('Subject') ?? '(без темы)';
    final from = appData.childText('From') ?? '';
    final to = appData.childText('To');
    final read = (appData.childText('Read') ?? '0') == '1';
    final dateRaw = appData.childText('DateReceived');
    DateTime? date;
    if (dateRaw != null && dateRaw.isNotEmpty) {
      date = DateTime.tryParse(dateRaw);
    }

    String? body;
    String? bodyHtml;
    final bodyNode = appData.child('Body');
    if (bodyNode != null) {
      final data = bodyNode.childText('Data') ?? bodyNode.text;
      final nativeType = bodyNode.childText('NativeBodyType');
      if (nativeType == '2' || (data != null && _looksLikeHtml(data))) {
        bodyHtml = data;
      } else {
        body = data;
      }
    }

    final attachments = <MailAttachment>[];
    final attContainer = appData.child('Attachments');
    if (attContainer != null) {
      for (final att in attContainer.childrenNamed('Attachment')) {
        final ref = att.childText('FileReference');
        if (ref == null || ref.isEmpty) continue;
        attachments.add(
          MailAttachment(
            displayName: att.childText('DisplayName') ?? 'attachment',
            fileReference: ref,
            contentId: att.childText('ContentId'),
            isInline: (att.childText('IsInline') ?? '0') == '1',
          ),
        );
      }
    }

    return MailMessage(
      serverId: serverId,
      collectionId: collectionId,
      subject: subject,
      from: from,
      to: to,
      body: body,
      bodyHtml: bodyHtml,
      read: read,
      dateReceived: date,
      attachments: attachments,
    );
  }

  Uint8List _provisionInitial() => WbXmlCodec.encode(
        WbXmlCodec.element(
          EasCodePages.provision,
          'Provision',
          children: [
            WbXmlCodec.element(
              EasCodePages.provision,
              'Policies',
              children: [
                WbXmlCodec.element(
                  EasCodePages.provision,
                  'Policy',
                  children: [
                    WbXmlCodec.element(
                      EasCodePages.provision,
                      'PolicyType',
                      text: 'MS-EAS-Provisioning-WBXML',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

  Uint8List _provisionAcknowledge(String key) => WbXmlCodec.encode(
        WbXmlCodec.element(
          EasCodePages.provision,
          'Provision',
          children: [
            WbXmlCodec.element(
              EasCodePages.provision,
              'Policies',
              children: [
                WbXmlCodec.element(
                  EasCodePages.provision,
                  'Policy',
                  children: [
                    WbXmlCodec.element(
                      EasCodePages.provision,
                      'PolicyType',
                      text: 'MS-EAS-Provisioning-WBXML',
                    ),
                    WbXmlCodec.element(EasCodePages.provision, 'PolicyKey', text: key),
                    WbXmlCodec.element(EasCodePages.provision, 'Status', text: '1'),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

  Future<Uint8List> _command(String cmd, Uint8List body) async {
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'User': _username,
        'DeviceId': deviceId,
        'DeviceType': deviceType,
        'Cmd': cmd,
      },
    );

    final response = await http.post(
      uri,
      headers: {
        ..._authHeader(),
        'MS-ASProtocolVersion': protocolVersion,
        'Content-Type': 'application/vnd.ms-sync.wbxml',
        'User-Agent': 'EASMail-Flutter/1.0',
        if (policyKey != '0') 'X-MS-PolicyKey': policyKey,
      },
      body: body,
    );

    final newPolicy = response.headers['x-ms-policykey'];
    if (newPolicy != null && newPolicy.isNotEmpty) policyKey = newPolicy;

    if (response.statusCode == 401) {
      throw EasException(
        usesBearer ? 'Токен недействителен, войдите снова' : 'Неверный логин или пароль',
      );
    }
    if (response.statusCode != 200) {
      throw EasException('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }

    return Uint8List.fromList(response.bodyBytes);
  }

  Map<String, String> _authHeader() {
    if (usesBearer) {
      return {'Authorization': 'Bearer $accessToken'};
    }
    return {'Authorization': _basicAuth(_username, password)};
  }

  String _basicAuth(String user, String pass) =>
      'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

  static bool _looksLikeHtml(String text) {
    final t = text.trimLeft().toLowerCase();
    return t.startsWith('<!doctype') ||
        t.startsWith('<html') ||
        RegExp(r'<(p|div|br|table|span|body)\b', caseSensitive: false)
            .hasMatch(text);
  }
}

class EasException implements Exception {
  const EasException(this.message);
  final String message;
  @override
  String toString() => message;
}
