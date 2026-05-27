enum MailProtocol { eas, imap }

enum EasAuthType { basic, oauth }

class MailAccount {
  const MailAccount({
    required this.email,
    required this.password,
    this.protocol = MailProtocol.eas,
    this.serverUrl = '',
    this.domain,
    this.displayName,
    this.authType = EasAuthType.basic,
    this.accessToken,
    this.refreshToken,
    this.tokenExpiresAt,
    this.imapHost = '',
    this.imapPort = 993,
    this.imapSsl = true,
    this.smtpHost = '',
    this.smtpPort = 587,
    this.smtpSsl = true,
    this.imapUsername,
    this.signature = '',
    this.signatureOnCompose = false,
    this.signatureOnReply = false,
    this.signatureOnForward = false,
    this.senderIconPath,
  });

  final String email;
  final String password;
  final MailProtocol protocol;
  final String serverUrl;
  final String? domain;
  final String? displayName;
  final EasAuthType authType;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? tokenExpiresAt;

  final String imapHost;
  final int imapPort;
  final bool imapSsl;
  final String smtpHost;
  final int smtpPort;
  final bool smtpSsl;
  final String? imapUsername;

  // ── Signature ────────────────────────────────────────────────────────────
  final String signature;
  final bool signatureOnCompose;
  final bool signatureOnReply;
  final bool signatureOnForward;

  // ── Sender icon ──────────────────────────────────────────────────────────
  final String? senderIconPath;

  bool get isEas => protocol == MailProtocol.eas;
  bool get isImap => protocol == MailProtocol.imap;
  bool get usesOAuth => isEas && authType == EasAuthType.oauth;

  String get loginUsername => imapUsername?.trim().isNotEmpty == true
      ? imapUsername!.trim()
      : email;

  String get easUsername {
    if (domain != null && domain!.isNotEmpty && !email.contains('\\')) {
      return '$domain\\$email';
    }
    return email;
  }

  String get activeSyncUrl {
    var base = serverUrl.trim();
    if (!base.startsWith('http')) base = 'https://$base';
    base = base.replaceAll(RegExp(r'/+$'), '');
    if (!base.toLowerCase().contains('microsoft-server-activesync')) {
      base = '$base/Microsoft-Server-ActiveSync';
    }
    return base;
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'protocol': protocol.name,
        'serverUrl': serverUrl,
        'authType': authType.name,
        if (domain != null) 'domain': domain,
        if (displayName != null) 'displayName': displayName,
        if (accessToken != null) 'accessToken': accessToken,
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (tokenExpiresAt != null)
          'tokenExpiresAt': tokenExpiresAt!.toIso8601String(),
        'imapHost': imapHost,
        'imapPort': imapPort,
        'imapSsl': imapSsl,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpSsl': smtpSsl,
        if (imapUsername != null) 'imapUsername': imapUsername,
        'signature': signature,
        'signatureOnCompose': signatureOnCompose,
        'signatureOnReply': signatureOnReply,
        'signatureOnForward': signatureOnForward,
        if (senderIconPath != null) 'senderIconPath': senderIconPath,
      };

  factory MailAccount.fromJson(Map<String, dynamic> json) {
    final protocolName = json['protocol'] as String? ?? 'eas';
    final authName = json['authType'] as String? ?? 'basic';
    return MailAccount(
      email: json['email'] as String,
      password: json['password'] as String? ?? '',
      protocol: MailProtocol.values.firstWhere(
        (e) => e.name == protocolName,
        orElse: () => MailProtocol.eas,
      ),
      serverUrl: json['serverUrl'] as String? ?? '',
      domain: json['domain'] as String?,
      displayName: json['displayName'] as String?,
      authType: EasAuthType.values.firstWhere(
        (e) => e.name == authName,
        orElse: () => EasAuthType.basic,
      ),
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      tokenExpiresAt: json['tokenExpiresAt'] != null
          ? DateTime.tryParse(json['tokenExpiresAt'] as String)
          : null,
      imapHost: json['imapHost'] as String? ?? '',
      imapPort: json['imapPort'] as int? ?? 993,
      imapSsl: json['imapSsl'] as bool? ?? true,
      smtpHost: json['smtpHost'] as String? ?? '',
      smtpPort: json['smtpPort'] as int? ?? 587,
      smtpSsl: json['smtpSsl'] as bool? ?? true,
      imapUsername: json['imapUsername'] as String?,
      signature: json['signature'] as String? ?? '',
      signatureOnCompose: json['signatureOnCompose'] as bool? ?? false,
      signatureOnReply: json['signatureOnReply'] as bool? ?? false,
      signatureOnForward: json['signatureOnForward'] as bool? ?? false,
      senderIconPath: json['senderIconPath'] as String?,
    );
  }

  MailAccount copyWith({
    String? password,
    String? serverUrl,
    String? domain,
    String? displayName,
    String? accessToken,
    String? refreshToken,
    DateTime? tokenExpiresAt,
    String? imapHost,
    int? imapPort,
    bool? imapSsl,
    String? smtpHost,
    int? smtpPort,
    bool? smtpSsl,
    String? imapUsername,
    String? signature,
    bool? signatureOnCompose,
    bool? signatureOnReply,
    bool? signatureOnForward,
    String? senderIconPath,
    bool clearSenderIcon = false,
  }) =>
      MailAccount(
        email: email,
        password: password ?? this.password,
        protocol: protocol,
        serverUrl: serverUrl ?? this.serverUrl,
        domain: domain ?? this.domain,
        displayName: displayName ?? this.displayName,
        authType: authType,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
        imapHost: imapHost ?? this.imapHost,
        imapPort: imapPort ?? this.imapPort,
        imapSsl: imapSsl ?? this.imapSsl,
        smtpHost: smtpHost ?? this.smtpHost,
        smtpPort: smtpPort ?? this.smtpPort,
        smtpSsl: smtpSsl ?? this.smtpSsl,
        imapUsername: imapUsername ?? this.imapUsername,
        signature: signature ?? this.signature,
        signatureOnCompose: signatureOnCompose ?? this.signatureOnCompose,
        signatureOnReply: signatureOnReply ?? this.signatureOnReply,
        signatureOnForward: signatureOnForward ?? this.signatureOnForward,
        senderIconPath: clearSenderIcon ? null : (senderIconPath ?? this.senderIconPath),
      );
}
