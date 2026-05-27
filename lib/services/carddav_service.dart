import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/contact.dart';
import 'app_settings.dart';

class CardDavService {
  Future<List<Contact>> fetchContacts(CardDavConfig config) async {
    final headers = _authHeaders(config);
    final url = config.serverUrl.endsWith('/')
        ? config.serverUrl
        : '${config.serverUrl}/';

    const reportBody = '''<?xml version="1.0" encoding="UTF-8"?>
<C:addressbook-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:prop>
    <D:getetag/>
    <C:address-data/>
  </D:prop>
</C:addressbook-query>''';

    final request = http.Request('REPORT', Uri.parse(url));
    request.headers.addAll({
      ...headers,
      'Content-Type': 'application/xml; charset=UTF-8',
      'Depth': '1',
    });
    request.body = reportBody;

    final streamedResponse = await http.Client().send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 401) {
      throw Exception('Неверные учётные данные CardDAV');
    }
    if (response.statusCode != 207) {
      throw Exception('CardDAV ошибка: ${response.statusCode}');
    }

    return _parseMultiStatus(response.body);
  }

  List<Contact> _parseMultiStatus(String xml) {
    final contacts = <Contact>[];
    final addressDataPattern = RegExp(
      r'<(?:\w+:)?address-data[^>]*>([\s\S]*?)</(?:\w+:)?address-data>',
      dotAll: true,
    );
    for (final match in addressDataPattern.allMatches(xml)) {
      final vcard = match.group(1) ?? '';
      if (vcard.trim().isNotEmpty) {
        final contact = _parseVCard(vcard.trim());
        if (contact != null) contacts.add(contact);
      }
    }
    return contacts;
  }

  Contact? _parseVCard(String vcard) {
    String? uid;
    String? displayName;
    final emails = <String>[];
    final phones = <String>[];
    String? organization;

    final lines = _unfoldVCard(vcard);

    for (final line in lines) {
      if (line.isEmpty) continue;
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;

      final propFull = line.substring(0, colonIdx).toUpperCase();
      final propName = propFull.split(';').first;
      final value = line.substring(colonIdx + 1).trim();

      switch (propName) {
        case 'UID':
          uid = value;
        case 'FN':
          displayName = _decodeValue(value);
        case 'EMAIL':
          if (value.isNotEmpty) emails.add(value);
        case 'TEL':
          if (value.isNotEmpty) phones.add(value);
        case 'ORG':
          final orgPart = value.split(';').first;
          if (orgPart.isNotEmpty) organization = _decodeValue(orgPart);
      }
    }

    if (displayName == null || displayName.isEmpty) return null;
    return Contact(
      uid: uid ?? displayName,
      displayName: displayName,
      emails: emails,
      phones: phones,
      organization: organization,
    );
  }

  List<String> _unfoldVCard(String vcard) {
    final result = <String>[];
    for (final rawLine in vcard.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isNotEmpty && (line[0] == ' ' || line[0] == '\t')) {
        if (result.isNotEmpty) {
          result[result.length - 1] = result.last + line.substring(1);
        }
      } else {
        result.add(line);
      }
    }
    return result;
  }

  String _decodeValue(String value) => value
      .replaceAll('\\n', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\');

  Map<String, String> _authHeaders(CardDavConfig config) {
    final credentials =
        base64Encode(utf8.encode('${config.username}:${config.password}'));
    return {'Authorization': 'Basic $credentials'};
  }
}
