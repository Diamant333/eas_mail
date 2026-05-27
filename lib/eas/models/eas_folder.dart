class EasFolder {
  const EasFolder({
    required this.serverId,
    required this.displayName,
    required this.type,
    this.parentId,
  });

  final String serverId;
  final String displayName;
  final int type;
  final String? parentId;

  bool get isInbox => type == 2;
}
