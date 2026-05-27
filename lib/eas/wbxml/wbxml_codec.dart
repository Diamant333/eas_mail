import 'dart:convert';
import 'dart:typed_data';

import 'code_pages.dart';
import 'wbxml_node.dart';

/// Кодирование и декодирование WBXML 1.3 для Exchange ActiveSync.
class WbXmlCodec {
  static const int _version = 0x03;
  static const int _switchPage = 0x00;
  static const int _end = 0x01;
  static const int _strI = 0x03;
  static const int _opaque = 0xC3;

  /// Элемент для кодирования: [page] — ID кодовой страницы EAS.
  static WbXmlNode element(
    int page,
    String tag, {
    String? text,
    List<WbXmlNode>? children,
  }) {
    return WbXmlNode(
      name: tag,
      page: page,
      text: text,
      children: children,
    );
  }

  static Uint8List encode(WbXmlNode root) {
    final body = <int>[];
    // По спецификации WBXML активная страница в начале документа — 0.
    _encodeNode(body, root, currentPage: 0);
  // Заголовок WBXML 1.3: version, publicId (mb), charset (mb), string table len (mb).
    return Uint8List.fromList([
      _version,
      0x01, // PublicID = unknown
      0x6A, // Charset MIB 106 = UTF-8
      0x00, // пустая string table
      ...body,
    ]);
  }

  static void _encodeNode(List<int> out, WbXmlNode node, {required int currentPage}) {
    final page = node.page ?? currentPage;
    if (page != currentPage) {
      out.addAll([_switchPage, page]);
      currentPage = page;
    }

    final token = EasCodePages.token(page, node.name);
    if (token == null) {
      throw FormatException('Неизвестный тег WBXML: ${node.name} (page $page)');
    }

    final hasContent =
        (node.text != null && node.text!.isNotEmpty) || node.children.isNotEmpty;

    if (hasContent) {
      out.add(token | 0x40);
      if (node.text != null && node.text!.isNotEmpty) {
        _writeInlineString(out, node.text!);
      }
      for (final child in node.children) {
        _encodeNode(out, child, currentPage: page);
      }
      out.add(_end);
    } else {
      out.add(token);
    }
  }

  static void _writeInlineString(List<int> out, String value) {
    out.add(_strI);
    out.addAll(utf8.encode(value));
    out.add(0x00);
  }

  static WbXmlNode decode(Uint8List data) {
    if (data.length < 5) {
      throw const FormatException('Слишком короткий WBXML');
    }
    var i = 0;
    if (data[i++] != _version) {
      throw const FormatException('Неподдерживаемая версия WBXML');
    }
    final pubId = _readMbUint(data, i);
    i += pubId.$2;
    if (pubId.$1 == 0) {
      final off = _readMbUint(data, i);
      i += off.$2;
    }
    final charset = _readMbUint(data, i);
    i += charset.$2;
    final stLen = _readMbUint(data, i);
    i += stLen.$2;
    i += stLen.$1;

    final nodes = <_Frame>[];
    var page = 0;
    var pageInitialized = true;

    while (i < data.length) {
      final b = data[i++];
      if (b == _switchPage) {
        page = data[i++];
        pageInitialized = true;
        continue;
      }
      if (b == _end) {
        if (nodes.isEmpty) break;
        final frame = nodes.removeLast();
        if (nodes.isEmpty) return frame.node;
        nodes.last.node.children.add(frame.node);
        continue;
      }
      if (b == _strI) {
        final start = i;
        while (i < data.length && data[i] != 0) {
          i++;
        }
        final text = utf8.decode(data.sublist(start, i));
        i++; // null
        if (nodes.isNotEmpty) {
          final parent = nodes.last.node;
          if (parent.text == null) {
            parent.text = text;
          } else {
            parent.text = '${parent.text}$text';
          }
        }
        continue;
      }
      if (b == _opaque) {
        final len = _readMbUint(data, i);
        i += len.$2;
        final payload = utf8.decode(data.sublist(i, i + len.$1));
        i += len.$1;
        if (nodes.isNotEmpty) {
          nodes.last.node.text = payload;
        }
        continue;
      }

      if (!pageInitialized) {
        throw const FormatException('Тег до SWITCH_PAGE');
      }

      final hasContent = (b & 0x40) != 0;
      final token = b & 0x3F;
      final name = EasCodePages.tagName(page, token);
      if (name == null) {
        throw FormatException('Неизвестный токен $token на странице $page');
      }

      final node = WbXmlNode(name: name, page: page);
      if (hasContent) {
        nodes.add(_Frame(node));
      } else if (nodes.isEmpty) {
        return node;
      } else {
        nodes.last.node.children.add(node);
      }
    }

    throw const FormatException('Некорректный WBXML');
  }

  static (int, int) _readMbUint(Uint8List data, int offset) {
    var value = 0;
    var count = 0;
    while (offset + count < data.length) {
      final b = data[offset + count];
      count++;
      value = (value << 7) | (b & 0x7F);
      if ((b & 0x80) == 0) break;
    }
    return (value, count);
  }
}

class _Frame {
  _Frame(this.node);
  final WbXmlNode node;
}
