import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LabelPreset {
  const LabelPreset({required this.name, required this.color});

  final String name;
  final int color;

  LabelPreset copyWith({String? name, int? color}) =>
      LabelPreset(name: name ?? this.name, color: color ?? this.color);

  Map<String, dynamic> toJson() => {'name': name, 'color': color};

  factory LabelPreset.fromJson(Map<String, dynamic> json) => LabelPreset(
        name: json['name'] as String,
        color: json['color'] as int,
      );

  static const defaultPresets = [
    LabelPreset(name: 'Красный', color: 0xFFFFCDD2),
    LabelPreset(name: 'Оранжевый', color: 0xFFFFE0B2),
    LabelPreset(name: 'Жёлтый', color: 0xFFFFF9C4),
    LabelPreset(name: 'Зелёный', color: 0xFFC8E6C9),
    LabelPreset(name: 'Голубой', color: 0xFFB3E5FC),
    LabelPreset(name: 'Синий', color: 0xFFBBDEFB),
    LabelPreset(name: 'Фиолетовый', color: 0xFFE1BEE7),
    LabelPreset(name: 'Серый', color: 0xFFE0E0E0),
  ];
}

class CardDavConfig {
  const CardDavConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.displayName,
  });

  final String serverUrl;
  final String username;
  final String password;
  final String? displayName;

  String get label => displayName?.isNotEmpty == true ? displayName! : serverUrl;

  CardDavConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? displayName,
  }) =>
      CardDavConfig(
        serverUrl: serverUrl ?? this.serverUrl,
        username: username ?? this.username,
        password: password ?? this.password,
        displayName: displayName ?? this.displayName,
      );

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        if (displayName != null) 'displayName': displayName,
      };

  factory CardDavConfig.fromJson(Map<String, dynamic> json) => CardDavConfig(
        serverUrl: json['serverUrl'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
        displayName: json['displayName'] as String?,
      );
}

enum FolderSortOrder {
  serverOrder,
  alphabetical,
  systemFirst,
}

class AppSettings {
  static const _syncIntervalKey = 'sync_interval_seconds';
  static const _labelPresetsKey = 'label_presets_v1';
  static const _carddavConfigsKey = 'carddav_configs_v1';
  static const _folderSortOrderKey = 'folder_sort_order';
  static const _splashImagePathKey = 'splash_image_path';
  static const _appNameKey = 'app_name';

  int syncIntervalSeconds = 300;
  List<LabelPreset> labelPresets = List.from(LabelPreset.defaultPresets);
  List<CardDavConfig> carddavConfigs = [];
  FolderSortOrder folderSortOrder = FolderSortOrder.serverOrder;
  String? splashImagePath;
  String appName = 'EAS Mail';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    syncIntervalSeconds = prefs.getInt(_syncIntervalKey) ?? 300;

    final presetsRaw = prefs.getString(_labelPresetsKey);
    if (presetsRaw != null) {
      try {
        final list = jsonDecode(presetsRaw) as List<dynamic>;
        labelPresets =
            list.map((e) => LabelPreset.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        labelPresets = List.from(LabelPreset.defaultPresets);
      }
    }

    final carddavRaw = prefs.getString(_carddavConfigsKey);
    if (carddavRaw != null) {
      try {
        final list = jsonDecode(carddavRaw) as List<dynamic>;
        carddavConfigs =
            list.map((e) => CardDavConfig.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        carddavConfigs = [];
      }
    }

    final sortRaw = prefs.getString(_folderSortOrderKey);
    if (sortRaw != null) {
      folderSortOrder = FolderSortOrder.values.firstWhere(
        (e) => e.name == sortRaw,
        orElse: () => FolderSortOrder.serverOrder,
      );
    }

    splashImagePath = prefs.getString(_splashImagePathKey);
    appName = prefs.getString(_appNameKey) ?? 'EAS Mail';
  }

  Future<void> setSyncInterval(int seconds) async {
    syncIntervalSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncIntervalKey, seconds);
  }

  Future<void> setLabelPresets(List<LabelPreset> presets) async {
    labelPresets = presets;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _labelPresetsKey,
      jsonEncode(presets.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> setCarddavConfigs(List<CardDavConfig> configs) async {
    carddavConfigs = configs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _carddavConfigsKey,
      jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> setFolderSortOrder(FolderSortOrder order) async {
    folderSortOrder = order;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderSortOrderKey, order.name);
  }

  Future<void> setSplashImagePath(String? path) async {
    splashImagePath = path;
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString(_splashImagePathKey, path);
    } else {
      await prefs.remove(_splashImagePathKey);
    }
  }

  Future<void> setAppName(String name) async {
    appName = name.trim().isEmpty ? 'EAS Mail' : name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appNameKey, appName);
  }
}
