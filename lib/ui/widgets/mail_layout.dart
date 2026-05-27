import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/message_layout.dart';
import '../../services/mail_session.dart';
import 'folder_tree_panel.dart';
import 'message_detail_panel.dart';
import 'message_list_panel.dart';

class MailLayout extends StatelessWidget {
  const MailLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    const listPanel = MessageListPanel();
    const detailPanel = MessageDetailPanel();
    const folderPanel = FolderTreePanel();

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final showFolders = constraints.maxWidth >= 900 && session.folders.isNotEmpty;

        if (narrow) {
          if (session.selectedMessage == null) {
            return Row(
              children: [
                if (session.folders.isNotEmpty) ...[
                  folderPanel,
                  const VerticalDivider(width: 1),
                ],
                const Expanded(child: listPanel),
              ],
            );
          }
          return Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => session.selectMessage(null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('К списку'),
                ),
              ),
              const Expanded(child: detailPanel),
            ],
          );
        }

        switch (session.paneLayout) {
          case MessagePaneLayout.detailRight:
            return Row(
              children: [
                if (showFolders) ...[
                  folderPanel,
                  const VerticalDivider(width: 1),
                ],
                const Expanded(flex: 2, child: listPanel),
                const VerticalDivider(width: 1),
                const Expanded(flex: 3, child: detailPanel),
              ],
            );
          case MessagePaneLayout.detailLeft:
            return Row(
              children: [
                if (showFolders) ...[
                  folderPanel,
                  const VerticalDivider(width: 1),
                ],
                const Expanded(flex: 3, child: detailPanel),
                const VerticalDivider(width: 1),
                const Expanded(flex: 2, child: listPanel),
              ],
            );
          case MessagePaneLayout.detailBottom:
            return Row(
              children: [
                if (showFolders) ...[
                  folderPanel,
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  child: Column(
                    children: const [
                      Expanded(flex: 2, child: listPanel),
                      Divider(height: 1),
                      Expanded(flex: 3, child: detailPanel),
                    ],
                  ),
                ),
              ],
            );
        }
      },
    );
  }
}
