import 'package:flutter_appauth/flutter_appauth.dart';

import '../config/oauth_config.dart';

class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.accessTokenExpiration,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? accessTokenExpiration;
}

class OAuthService {
  OAuthService({FlutterAppAuth? appAuth}) : _appAuth = appAuth ?? const FlutterAppAuth();

  final FlutterAppAuth _appAuth;

  Future<OAuthTokens> signIn() async {
    if (!OAuthConfig.isConfigured) {
      throw Exception(
        'Укажите Client ID в lib/config/oauth_config.dart (Azure App Registration)',
      );
    }

    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        OAuthConfig.clientId,
        OAuthConfig.redirectUrl,
        discoveryUrl: OAuthConfig.discoveryUrl,
        scopes: OAuthConfig.scopes,
        promptValues: ['login'],
      ),
    );

    if (result.accessToken == null) {
      throw Exception('OAuth: вход отменён или токен не получен');
    }

    return OAuthTokens(
      accessToken: result.accessToken!,
      refreshToken: result.refreshToken,
      accessTokenExpiration: result.accessTokenExpirationDateTime,
    );
  }

  Future<OAuthTokens?> refresh(String refreshToken) async {
    if (!OAuthConfig.isConfigured) return null;

    final result = await _appAuth.token(
      TokenRequest(
        OAuthConfig.clientId,
        OAuthConfig.redirectUrl,
        refreshToken: refreshToken,
        discoveryUrl: OAuthConfig.discoveryUrl,
        scopes: OAuthConfig.scopes,
      ),
    );

    if (result.accessToken == null) return null;
    return OAuthTokens(
      accessToken: result.accessToken!,
      refreshToken: result.refreshToken ?? refreshToken,
      accessTokenExpiration: result.accessTokenExpirationDateTime,
    );
  }
}
