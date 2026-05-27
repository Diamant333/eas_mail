/// Расположение области просмотра письма относительно списка.
enum MessagePaneLayout {
  /// Список слева, письмо справа.
  detailRight,

  /// Список сверху, письмо снизу.
  detailBottom,

  /// Письмо слева, список справа.
  detailLeft,
}

extension MessagePaneLayoutX on MessagePaneLayout {
  String get title => switch (this) {
        MessagePaneLayout.detailRight => 'Справа',
        MessagePaneLayout.detailBottom => 'Снизу',
        MessagePaneLayout.detailLeft => 'Слева',
      };

  static MessagePaneLayout fromName(String? name) {
    return MessagePaneLayout.values.firstWhere(
      (e) => e.name == name,
      orElse: () => MessagePaneLayout.detailRight,
    );
  }
}
