import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AccountFolderPrefs {
  static String _orderKey(String email) => 'folder_order_v1_$email';
  static String _hiddenKey(String email) => 'folder_hidden_v1_$email';

  List<String> customOrder = [];
  Set<String> hiddenFolderIds = {};

  Future<void> load(String email) async {
    final prefs = await SharedPreferences.getInstance();

    customOrder = [];
    final orderRaw = prefs.getString(_orderKey(email));
    if (orderRaw != null) {
      try {
        customOrder = (jsonDecode(orderRaw) as List).cast<String>();
      } catch (_) {}
    }

    hiddenFolderIds = {};
    final hiddenRaw = prefs.getString(_hiddenKey(email));
    if (hiddenRaw != null) {
      try {
        hiddenFolderIds = (jsonDecode(hiddenRaw) as List).cast<String>().toSet();
      } catch (_) {}
    }
  }

  Future<void> saveOrder(String email, List<String> order) async {
    customOrder = order;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orderKey(email), jsonEncode(order));
  }

  Future<void> saveHidden(String email, Set<String> hidden) async {
    hiddenFolderIds = hidden;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hiddenKey(email), jsonEncode(hidden.toList()));
  }
}
