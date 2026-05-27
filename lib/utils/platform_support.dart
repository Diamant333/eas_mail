import 'package:flutter/foundation.dart';

/// IMAP/SMTP используют RawSocket (dart:io) — недоступно во Flutter Web.
bool get supportsImapSmtp => !kIsWeb;

/// EAS использует HTTP — работает и в браузере (с ограничениями CORS/прокси).
bool get supportsEas => true;

String? connectionBlockedReason({required bool imap}) {
  if (imap && kIsWeb) {
    return 'IMAP/SMTP нельзя использовать в браузере (ошибка RawSocket). '
        'Запустите приложение на Windows или Android:\n'
        'flutter run -d windows';
  }
  return null;
}

String humanizeConnectionError(Object error) {
  final text = error.toString();
  if (text.contains('RawSocket') || text.contains('Unsupported operation')) {
    if (kIsWeb) {
      return 'Сетевые сокеты недоступны в браузере. '
          'Для IMAP используйте: flutter run -d windows или flutter run -d android. '
          'Для Exchange в браузере попробуйте режим EAS (если сервер разрешает HTTP).';
    }
    return 'Ошибка сетевого сокета: $text';
  }
  return text;
}
