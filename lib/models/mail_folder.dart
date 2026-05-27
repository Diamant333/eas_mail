enum MailFolderType { inbox, sent, trash, drafts, spam, other }

class MailFolder {
  const MailFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.type = MailFolderType.other,
    this.unreadCount = 0,
    this.totalCount = 0,
  });

  final String id;
  final String name;
  final String? parentId;
  final MailFolderType type;
  final int unreadCount;
  final int totalCount;

  bool get isInbox => type == MailFolderType.inbox;
  bool get isSent => type == MailFolderType.sent;
  bool get isTrash => type == MailFolderType.trash;
  bool get isDrafts => type == MailFolderType.drafts;

  MailFolder copyWith({int? unreadCount, int? totalCount}) => MailFolder(
        id: id,
        name: name,
        parentId: parentId,
        type: type,
        unreadCount: unreadCount ?? this.unreadCount,
        totalCount: totalCount ?? this.totalCount,
      );
}
