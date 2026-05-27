/// Узел XML-дерева после декодирования WBXML.
class WbXmlNode {
  WbXmlNode({
    required this.name,
    this.page,
    this.text,
    List<WbXmlNode>? children,
  }) : children = children ?? [];

  final String name;
  final int? page;
  String? text;
  final List<WbXmlNode> children;

  String? childText(String name) {
    for (final c in children) {
      if (c.name == name) {
        if (c.text != null && c.text!.isNotEmpty) return c.text;
        if (c.children.length == 1 && c.children.first.text != null) {
          return c.children.first.text;
        }
        return c.text;
      }
    }
    return null;
  }

  WbXmlNode? child(String name) {
    for (final c in children) {
      if (c.name == name) return c;
    }
    return null;
  }

  List<WbXmlNode> childrenNamed(String name) {
    return children.where((c) => c.name == name).toList();
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        if (text != null) 'text': text,
        if (children.isNotEmpty)
          'children': children.map((c) => c.toMap()).toList(),
      };
}
