import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mail_folder.dart';
import '../../services/app_settings.dart';
import '../../services/mail_session.dart';

class FolderTreePanel extends StatefulWidget {
  const FolderTreePanel({super.key});

  @override
  State<FolderTreePanel> createState() => _FolderTreePanelState();
}

class _FolderTreePanelState extends State<FolderTreePanel> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final folders = session.folders;

    if (folders.isEmpty) {
      return const SizedBox.shrink();
    }

    var roots = folders
        .where((f) =>
            f.parentId == null ||
            f.parentId!.isEmpty ||
            f.parentId == '0')
        .toList();
    final children = <String, List<MailFolder>>{};
    for (final f in folders) {
      if (f.parentId != null &&
          f.parentId!.isNotEmpty &&
          f.parentId != '0') {
        children.putIfAbsent(f.parentId!, () => []).add(f);
      }
    }

    final folderPrefs = session.folderPrefs;
    final hiddenIds = folderPrefs.hiddenFolderIds;
    final customOrder = folderPrefs.customOrder;

    // Filter hidden folders.
    roots = roots.where((f) => !hiddenIds.contains(f.id)).toList();
    for (final key in children.keys) {
      children[key] =
          children[key]!.where((f) => !hiddenIds.contains(f.id)).toList();
    }

    // Sort.
    if (customOrder.isNotEmpty) {
      final orderMap = {
        for (var i = 0; i < customOrder.length; i++) customOrder[i]: i
      };
      roots.sort((a, b) {
        final ai = orderMap[a.id] ?? 9999;
        final bi = orderMap[b.id] ?? 9999;
        return ai.compareTo(bi);
      });
      for (final key in children.keys) {
        children[key]!.sort((a, b) {
          final ai = orderMap[a.id] ?? 9999;
          final bi = orderMap[b.id] ?? 9999;
          return ai.compareTo(bi);
        });
      }
    } else {
      final sortOrder = session.settings.folderSortOrder;
      roots = _sorted(roots, sortOrder);
      for (final key in children.keys) {
        children[key] = _sorted(children[key]!, sortOrder);
      }
    }

    return Container(
      width: 220,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              session.account?.email ?? 'Папки',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final folder in roots) ...[
                  _FolderTile(
                    folder: folder,
                    depth: 0,
                    isExpanded: _expanded.contains(folder.id),
                    hasChildren: children.containsKey(folder.id),
                    onExpand: () => setState(() {
                      if (_expanded.contains(folder.id)) {
                        _expanded.remove(folder.id);
                      } else {
                        _expanded.add(folder.id);
                      }
                    }),
                  ),
                  if (_expanded.contains(folder.id))
                    for (final child in (children[folder.id] ?? []))
                      _FolderTile(
                        folder: child,
                        depth: 1,
                        isExpanded: _expanded.contains(child.id),
                        hasChildren: children.containsKey(child.id),
                        onExpand: () => setState(() {
                          if (_expanded.contains(child.id)) {
                            _expanded.remove(child.id);
                          } else {
                            _expanded.add(child.id);
                          }
                        }),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<MailFolder> _sorted(
      List<MailFolder> src, FolderSortOrder order) {
    final list = List<MailFolder>.from(src);
    switch (order) {
      case FolderSortOrder.alphabetical:
        list.sort((a, b) => a.name.compareTo(b.name));
      case FolderSortOrder.systemFirst:
        list.sort((a, b) {
          final aSystem = a.type != MailFolderType.other ? 0 : 1;
          final bSystem = b.type != MailFolderType.other ? 0 : 1;
          if (aSystem != bSystem) return aSystem - bSystem;
          return a.name.compareTo(b.name);
        });
      case FolderSortOrder.serverOrder:
        break;
    }
    return list;
  }
}

// ── Folder tile ───────────────────────────────────────────────────────────────

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.depth,
    required this.isExpanded,
    required this.hasChildren,
    required this.onExpand,
  });

  final MailFolder folder;
  final int depth;
  final bool isExpanded;
  final bool hasChildren;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final selected = session.selectedFolderId == folder.id;

    final unread = folder.unreadCount;
    final total = folder.totalCount;
    final hasUnread = unread > 0;

    // Build the count label.
    String? countLabel;
    if (total > 0) {
      countLabel = hasUnread ? '$unread/$total' : '$total';
    }

    // Select folder deferred via microtask to avoid the
    // !_debugDuringDeviceUpdate assertion from mouse-event processing.
    void onTap() => Future.microtask(() => session.selectFolder(folder.id));

    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.6)
            : null,
        padding: EdgeInsets.only(
          left: 12.0 + depth * 16.0,
          right: 4,
          top: 4,
          bottom: 4,
        ),
        child: Row(
          children: [
            if (hasChildren)
              GestureDetector(
                onTap: onExpand,
                child: Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              )
            else
              const SizedBox(width: 18),
            const SizedBox(width: 4),
            Icon(
              _folderIcon(folder.type),
              size: 18,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                countLabel != null
                    ? '${folder.name} ($countLabel)'
                    : folder.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: selected
                          ? FontWeight.w600
                          : (hasUnread ? FontWeight.bold : FontWeight.normal),
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _folderIcon(MailFolderType type) {
    switch (type) {
      case MailFolderType.inbox:
        return Icons.inbox_outlined;
      case MailFolderType.sent:
        return Icons.send_outlined;
      case MailFolderType.trash:
        return Icons.delete_outline;
      case MailFolderType.drafts:
        return Icons.drafts_outlined;
      case MailFolderType.spam:
        return Icons.report_outlined;
      case MailFolderType.other:
        return Icons.folder_outlined;
    }
  }
}
