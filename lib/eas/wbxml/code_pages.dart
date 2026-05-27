/// Таблицы кодовых страниц EAS (MS-ASWBXML, версия 14.1+).
class EasCodePages {
  EasCodePages._();

  static const int airSync = 0;
  static const int email = 2;
  static const int folderHierarchy = 7;
  static const int provision = 14;
  static const int airSyncBase = 17;
  static const int itemOperations = 20;
  static const int composeMail = 21;

  static final Map<int, Map<int, String>> _byPageToken = {};
  static final Map<int, Map<String, int>> _byPageName = {};

  static void _register(int page, List<(int, String)> tags) {
    _byPageToken[page] = {for (final t in tags) t.$1: t.$2};
    _byPageName[page] = {for (final t in tags) t.$2: t.$1};
  }

  static void _init() {
    if (_byPageToken.isNotEmpty) return;

    _register(airSync, [
      (0x05, 'Sync'),
      (0x07, 'Add'),
      (0x08, 'Change'),
      (0x09, 'Delete'),
      (0x0A, 'Fetch'),
      (0x0B, 'SyncKey'),
      (0x0C, 'ClientId'),
      (0x0D, 'ServerId'),
      (0x0E, 'Status'),
      (0x0F, 'Collection'),
      (0x10, 'Class'),
      (0x12, 'CollectionId'),
      (0x13, 'GetChanges'),
      (0x14, 'MoreAvailable'),
      (0x15, 'WindowSize'),
      (0x17, 'Options'),
      (0x1C, 'Collections'),
      (0x1D, 'ApplicationData'),
      (0x22, 'MIMESupport'),
      (0x23, 'MIMETruncation'),
    ]);

    _register(email, [
      (0x0F, 'DateReceived'),
      (0x11, 'DisplayTo'),
      (0x12, 'Importance'),
      (0x13, 'MessageClass'),
      (0x14, 'Subject'),
      (0x15, 'Read'),
      (0x16, 'To'),
      (0x17, 'Cc'),
      (0x18, 'From'),
    ]);

    _register(folderHierarchy, [
      (0x07, 'DisplayName'),
      (0x08, 'ServerId'),
      (0x09, 'ParentId'),
      (0x0A, 'Type'),
      (0x0C, 'Status'),
      (0x0E, 'Changes'),
      (0x0F, 'Add'),
      (0x10, 'Delete'),
      (0x11, 'Update'),
      (0x12, 'SyncKey'),
      (0x16, 'FolderSync'),
    ]);

    _register(provision, [
      (0x05, 'Provision'),
      (0x06, 'Policies'),
      (0x07, 'Policy'),
      (0x08, 'PolicyType'),
      (0x09, 'PolicyKey'),
      (0x0A, 'Data'),
      (0x0B, 'Status'),
      (0x0D, 'EASProvisionDoc'),
    ]);

    _register(airSyncBase, [
      (0x05, 'BodyPreference'),
      (0x06, 'Type'),
      (0x07, 'TruncationSize'),
      (0x0A, 'Body'),
      (0x0B, 'Data'),
      (0x0E, 'Attachments'),
      (0x0F, 'Attachment'),
      (0x10, 'DisplayName'),
      (0x11, 'FileReference'),
      (0x12, 'Method'),
      (0x13, 'ContentId'),
      (0x14, 'ContentLocation'),
      (0x15, 'IsInline'),
      (0x16, 'NativeBodyType'),
    ]);

    _register(itemOperations, [
      (0x05, 'ItemOperations'),
      (0x06, 'Fetch'),
      (0x07, 'Store'),
      (0x08, 'Options'),
      (0x09, 'Range'),
      (0x0B, 'Properties'),
      (0x0C, 'Data'),
      (0x0D, 'Status'),
      (0x0E, 'Response'),
    ]);

    _register(composeMail, [
      (0x05, 'SendMail'),
      (0x08, 'SaveInSentItems'),
      (0x10, 'MIME'),
      (0x11, 'ClientId'),
      (0x12, 'Status'),
    ]);
  }

  static String? tagName(int page, int token) {
    _init();
    return _byPageToken[page]?[token];
  }

  static int? token(int page, String name) {
    _init();
    return _byPageName[page]?[name];
  }
}
