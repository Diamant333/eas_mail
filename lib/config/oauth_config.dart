/// Настройки OAuth для Microsoft 365 / Exchange Online.
///
/// 1. Зарегистрируйте приложение: https://portal.azure.com → App registrations
/// 2. Добавьте redirect URI: com.easmail://oauth
/// 3. API permissions: Office 365 Exchange Online → EAS.AccessAsUser.All
/// 4. Вставьте Client ID ниже.
class OAuthConfig {
  OAuthConfig._();

  /// Замените на Client ID из Azure Portal.
  static const String clientId = '00000000-0000-0000-0000-000000000000';

  static const String redirectUrl = 'com.easmail://oauth';

  static const String discoveryUrl =
      'https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration';

  /// Scopes для Exchange ActiveSync (Office 365).
  static const List<String> scopes = [
    'https://outlook.office.com/EAS.AccessAsUser.All',
    'offline_access',
    'openid',
    'profile',
    'email',
  ];

  static bool get isConfigured =>
      clientId != '00000000-0000-0000-0000-000000000000' && clientId.isNotEmpty;
}
