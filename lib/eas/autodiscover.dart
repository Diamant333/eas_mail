import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

/// Упрощённый Autodiscover (POX) для получения URL ActiveSync.
class EasAutodiscover {
  static Future<String?> discoverActiveSyncUrl({
    required String email,
    String password = '',
    String? domain,
    String? bearerToken,
  }) async {
    final host = email.contains('@') ? email.split('@').last : email;
    final candidates = [
      'https://autodiscover.$host/autodiscover/autodiscover.xml',
      'https://$host/autodiscover/autodiscover.xml',
    ];

    final authUser = domain != null && domain.isNotEmpty && !email.contains('\\')
        ? '$domain\\$email'
        : email;

    for (final url in candidates) {
      try {
        final body = _buildRequest(email);
        final headers = <String, String>{
          'Content-Type': 'text/xml; charset=utf-8',
        };
        if (bearerToken != null && bearerToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $bearerToken';
        } else if (password.isNotEmpty) {
          headers['Authorization'] = _basicAuth(authUser, password);
        }

        final response = await http.post(Uri.parse(url), headers: headers, body: body);
        if (response.statusCode != 200) continue;
        final doc = xml.XmlDocument.parse(response.body);
        for (final element in doc.findAllElements('Url')) {
          final u = element.innerText.trim();
          if (u.toLowerCase().contains('microsoft-server-activesync')) {
            return u;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static String _buildRequest(String email) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006">
  <Request>
    <EMailAddress>$email</EMailAddress>
    <AcceptableResponseSchema>http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006</AcceptableResponseSchema>
  </Request>
</Autodiscover>''';
  }

  static String _basicAuth(String user, String password) {
    final token = base64Encode(utf8.encode('$user:$password'));
    return 'Basic $token';
  }
}
