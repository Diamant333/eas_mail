import 'package:shared_preferences/shared_preferences.dart';

import '../models/message_layout.dart';

class LayoutPrefs {
  static const _key = 'message_pane_layout';

  Future<MessagePaneLayout> load() async {
    final prefs = await SharedPreferences.getInstance();
    return MessagePaneLayoutX.fromName(prefs.getString(_key));
  }

  Future<void> save(MessagePaneLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, layout.name);
  }
}
