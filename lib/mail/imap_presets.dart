class ImapPreset {
  const ImapPreset({
    required this.id,
    required this.label,
    required this.imapHost,
    this.imapPort = 993,
    this.imapSsl = true,
    required this.smtpHost,
    this.smtpPort = 587,
    this.smtpSsl = true,
  });

  final String id;
  final String label;
  final String imapHost;
  final int imapPort;
  final bool imapSsl;
  final String smtpHost;
  final int smtpPort;
  final bool smtpSsl;
}

class ImapPresets {
  ImapPresets._();

  static const custom = ImapPreset(
    id: 'custom',
    label: 'Вручную',
    imapHost: '',
    smtpHost: '',
  );

  static const all = [
    ImapPreset(
      id: 'gmail',
      label: 'Gmail',
      imapHost: 'imap.gmail.com',
      smtpHost: 'smtp.gmail.com',
      smtpPort: 587,
    ),
    ImapPreset(
      id: 'yandex',
      label: 'Яндекс',
      imapHost: 'imap.yandex.ru',
      smtpHost: 'smtp.yandex.ru',
      smtpPort: 465,
      smtpSsl: true,
    ),
    ImapPreset(
      id: 'mailru',
      label: 'Mail.ru',
      imapHost: 'imap.mail.ru',
      smtpHost: 'smtp.mail.ru',
      smtpPort: 465,
      smtpSsl: true,
    ),
    ImapPreset(
      id: 'outlook',
      label: 'Outlook.com',
      imapHost: 'outlook.office365.com',
      smtpHost: 'smtp.office365.com',
      smtpPort: 587,
    ),
    custom,
  ];

  static ImapPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static ImapPreset? guessFromEmail(String email) {
    if (!email.contains('@')) return null;
    final domain = email.split('@').last.toLowerCase();
    if (domain == 'gmail.com' || domain == 'googlemail.com') return all[0];
    if (domain == 'yandex.ru' || domain == 'ya.ru') return all[1];
    if (domain == 'mail.ru' || domain == 'inbox.ru' || domain == 'list.ru') {
      return all[2];
    }
    if (domain == 'outlook.com' || domain == 'hotmail.com' || domain == 'live.com') {
      return all[3];
    }
    return null;
  }
}
