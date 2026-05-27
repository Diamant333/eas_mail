# EAS Mail

Почтовый клиент на **Flutter** с поддержкой **Microsoft Exchange ActiveSync (EAS 16.1)**.

## Возможности

- Вход по email и паролю (Basic Auth)
- **IMAP / SMTP** (Gmail, Яндекс, Mail.ru, Outlook.com и др.)
- **OAuth2** для Microsoft 365 / Exchange Online
- Autodiscover для поиска URL ActiveSync
- Provision, FolderSync, Sync (входящие)
- **Отправка писем** с вложениями (SendMail)
- **Скачивание вложений** (ItemOperations)
- Список писем и просмотр текста
- Сохранение учётной записи в защищённом хранилище

## Требования

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.16+
- Сервер Exchange / Exchange Online с включённым ActiveSync
- Для Exchange Online с марта 2026 требуется **EAS 16.1** (указано в клиенте)

## Запуск

```bash
cd eas_mail
flutter pub get
flutter run -d windows
```

Другие платформы:

```bash
flutter run -d android
flutter run -d ios
```

## Настройка учётной записи

### IMAP / SMTP

1. На экране входа выберите **IMAP**.
2. Укажите **email** и **пароль** (для Gmail — [пароль приложения](https://support.google.com/accounts/answer/185833)).
3. Выберите провайдера из списка или настройте серверы вручную.
4. Включите **Автонастройку IMAP**, чтобы определить серверы по email.

### Basic Auth (on-premise / локальный Exchange)

1. Укажите **email** и **пароль**.
2. При необходимости — **домен** Windows (`DOMAIN\user`).
3. Сервер можно оставить пустым, если включён **Autodiscover**.
4. Или укажите вручную, например: `mail.company.ru`

### OAuth2 (Microsoft 365)

1. Зарегистрируйте приложение в [Azure Portal](https://portal.azure.com) → App registrations.
2. Redirect URI: `com.easmail://oauth`
3. API permissions: **Office 365 Exchange Online** → `EAS.AccessAsUser.All`, `offline_access`
4. Скопируйте **Application (client) ID** в `lib/config/oauth_config.dart`
5. В приложении выберите **Microsoft 365** и нажмите «Войти через Microsoft».

## Архитектура

```
lib/
  eas/              Протокол EAS (WBXML, HTTP, команды)
  services/         Сессия и хранение учётных данных
  ui/screens/       Экраны приложения
```

## Ограничения (MVP)

- Нет календаря и контактов
- OAuth требует настройки Azure App Registration
- Некоторые серверы требуют регистрации устройства или MFA
- HTML-тело писем отображается как текст
- Крупные вложения могут обрезаться лимитом сервера

## Безопасность

Пароль хранится локально через `flutter_secure_storage`. Не используйте на общих устройствах без шифрования диска.

## Лицензия

Учебный / демонстрационный проект.
