import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/message_meta.dart';

class MessageMetaStore {
  static const _key = 'message_meta_v1';

  Map<String, MessageMeta> _cache = {};

  static String messageKey(String collectionId, String serverId) =>
      '$collectionId:$serverId';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      _cache = {};
      return;
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _cache = map.map(
      (k, v) => MapEntry(k, MessageMeta.fromJson(v as Map<String, dynamic>)),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _cache.map((k, v) => MapEntry(k, v.toJson())),
    );
    await prefs.setString(_key, encoded);
  }

  MessageMeta getMeta(String key) => _cache[key] ?? const MessageMeta();

  Future<void> setMeta(String key, MessageMeta meta) async {
    _cache[key] = meta;
    await save();
  }
}
