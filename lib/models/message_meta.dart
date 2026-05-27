class MessageMeta {
  const MessageMeta({
    this.labelName,
    this.labelColorValue,
    this.pinned = false,
  });

  final String? labelName;
  final int? labelColorValue;
  final bool pinned;

  bool get hasLabel => labelName != null && labelColorValue != null;

  MessageMeta copyWith({
    String? labelName,
    int? labelColorValue,
    bool? pinned,
    bool clearLabel = false,
  }) =>
      MessageMeta(
        labelName: clearLabel ? null : (labelName ?? this.labelName),
        labelColorValue:
            clearLabel ? null : (labelColorValue ?? this.labelColorValue),
        pinned: pinned ?? this.pinned,
      );

  Map<String, dynamic> toJson() => {
        if (labelName != null) 'labelName': labelName,
        if (labelColorValue != null) 'labelColorValue': labelColorValue,
        'pinned': pinned,
      };

  factory MessageMeta.fromJson(Map<String, dynamic> json) => MessageMeta(
        labelName: json['labelName'] as String?,
        labelColorValue: json['labelColorValue'] as int?,
        pinned: json['pinned'] as bool? ?? false,
      );
}

/// Предустановленные цвета меток.
class LabelColors {
  LabelColors._();

  static const presets = [
    (name: 'Красный', color: 0xFFFFCDD2),
    (name: 'Оранжевый', color: 0xFFFFE0B2),
    (name: 'Жёлтый', color: 0xFFFFF9C4),
    (name: 'Зелёный', color: 0xFFC8E6C9),
    (name: 'Голубой', color: 0xFFB3E5FC),
    (name: 'Синий', color: 0xFFBBDEFB),
    (name: 'Фиолетовый', color: 0xFFE1BEE7),
    (name: 'Серый', color: 0xFFE0E0E0),
  ];
}
