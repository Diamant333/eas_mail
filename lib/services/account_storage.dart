import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../mail/models/mail_account.dart';

class AccountStorage {
  AccountStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accountsKey = 'eas_accounts_v2';
  static const _legacyKey = 'eas_account';
  static const _activeIndexKey = 'eas_active_index';

  final FlutterSecureStorage _storage;

  Future<List<MailAccount>> loadAll() async {
    final newRaw = await _storage.read(key: _accountsKey);
    if (newRaw != null) {
      try {
        final list = jsonDecode(newRaw) as List<dynamic>;
        return list
            .map((e) => MailAccount.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    // Migrate from old single-account format.
    final oldRaw = await _storage.read(key: _legacyKey);
    if (oldRaw != null) {
      try {
        final json = jsonDecode(oldRaw) as Map<String, dynamic>;
        if (!json.containsKey('protocol')) json['protocol'] = 'eas';
        final account = MailAccount.fromJson(json);
        await saveAll([account]);
        await _storage.delete(key: _legacyKey);
        return [account];
      } catch (_) {}
    }

    return [];
  }

  Future<void> saveAll(List<MailAccount> accounts) async {
    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  Future<int> loadActiveIndex() async {
    final raw = await _storage.read(key: _activeIndexKey);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  Future<void> saveActiveIndex(int index) async {
    await _storage.write(key: _activeIndexKey, value: index.toString());
  }

  Future<void> clear() async {
    await _storage.delete(key: _accountsKey);
    await _storage.delete(key: _legacyKey);
    await _storage.delete(key: _activeIndexKey);
  }

  // --- Backward-compat helpers (used by OAuth flow) ---

  Future<MailAccount?> load() async {
    final all = await loadAll();
    return all.isEmpty ? null : all.first;
  }

  Future<void> save(MailAccount account) async {
    final all = await loadAll();
    final idx = all.indexWhere((a) => a.email == account.email);
    if (idx >= 0) {
      all[idx] = account;
    } else {
      all.add(account);
    }
    await saveAll(all);
  }
}
