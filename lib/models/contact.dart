class Contact {
  const Contact({
    required this.uid,
    required this.displayName,
    this.emails = const [],
    this.phones = const [],
    this.organization,
  });

  final String uid;
  final String displayName;
  final List<String> emails;
  final List<String> phones;
  final String? organization;

  String get primaryEmail => emails.isNotEmpty ? emails.first : '';

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'emails': emails,
        'phones': phones,
        if (organization != null) 'organization': organization,
      };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        uid: json['uid'] as String,
        displayName: json['displayName'] as String,
        emails: (json['emails'] as List<dynamic>?)?.cast<String>() ?? [],
        phones: (json['phones'] as List<dynamic>?)?.cast<String>() ?? [],
        organization: json['organization'] as String?,
      );
}
