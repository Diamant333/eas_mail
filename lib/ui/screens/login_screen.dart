import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/oauth_config.dart';
import '../../utils/platform_support.dart';
import '../../mail/imap_presets.dart';
import '../../mail/models/mail_account.dart';
import '../../services/mail_session.dart';
import 'mail_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.addMode = false});

  /// When true, navigates back instead of replacing root after login.
  final bool addMode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController();
  final _domain = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '587');

  MailProtocol _protocol = MailProtocol.eas;
  EasAuthType _authType = EasAuthType.basic;
  bool _useAutodiscover = true;
  String _imapPresetId = 'gmail';
  bool _imapSsl = true;
  bool _smtpSsl = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _protocol = MailProtocol.eas;
    _email.addListener(_onEmailChanged);
  }

  void _onEmailChanged() {
    if (_protocol != MailProtocol.imap) return;
    final guess = ImapPresets.guessFromEmail(_email.text.trim());
    if (guess != null && guess.id != 'custom') {
      setState(() => _imapPresetId = guess.id);
      _applyPreset(guess);
    }
  }

  void _applyPreset(ImapPreset preset) {
    _imapHost.text = preset.imapHost;
    _imapPort.text = preset.imapPort.toString();
    _smtpHost.text = preset.smtpHost;
    _smtpPort.text = preset.smtpPort.toString();
    _imapSsl = preset.imapSsl;
    _smtpSsl = preset.smtpSsl;
  }

  @override
  void dispose() {
    _email.removeListener(_onEmailChanged);
    _email.dispose();
    _password.dispose();
    _server.dispose();
    _domain.dispose();
    _imapHost.dispose();
    _imapPort.dispose();
    _smtpHost.dispose();
    _smtpPort.dispose();
    super.dispose();
  }

  Future<void> _connectBasic() async {
    if (!_formKey.currentState!.validate()) return;

    final session = context.read<MailSession>();
    if (_protocol == MailProtocol.imap) {
      final preset = ImapPresets.byId(_imapPresetId) ?? ImapPresets.custom;
      final account = MailAccount(
        email: _email.text.trim(),
        password: _password.text,
        protocol: MailProtocol.imap,
        imapHost: _imapHost.text.trim().isEmpty ? preset.imapHost : _imapHost.text.trim(),
        imapPort: int.tryParse(_imapPort.text) ?? preset.imapPort,
        imapSsl: _imapSsl,
        smtpHost: _smtpHost.text.trim().isEmpty ? preset.smtpHost : _smtpHost.text.trim(),
        smtpPort: int.tryParse(_smtpPort.text) ?? preset.smtpPort,
        smtpSsl: _smtpSsl,
      );
      await session.signIn(account, useAutodiscover: _useAutodiscover);
    } else {
      final account = MailAccount(
        email: _email.text.trim(),
        password: _password.text,
        protocol: MailProtocol.eas,
        serverUrl: _server.text.trim().isEmpty
            ? 'mail.${_email.text.trim().split('@').last}'
            : _server.text.trim(),
        domain: _domain.text.trim().isEmpty ? null : _domain.text.trim(),
        authType: EasAuthType.basic,
      );
      await session.signIn(account, useAutodiscover: _useAutodiscover);
    }
    _handleResult(session);
  }

  Future<void> _connectOAuth() async {
    final session = context.read<MailSession>();
    await session.signInWithOAuth(
      serverHint: _server.text.trim().isEmpty ? null : _server.text.trim(),
    );
    _handleResult(session);
  }

  void _handleResult(MailSession session) {
    if (!mounted) return;
    if (session.isSignedIn && session.error == null) {
      if (widget.addMode) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MailShell()),
        );
      }
    } else if (session.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final isEas = _protocol == MailProtocol.eas;
    final isOAuth = isEas && _authType == EasAuthType.oauth;
    final isCustomImap = _imapPresetId == ImapPresets.custom.id;

    return Scaffold(
      appBar: AppBar(title: const Text('EAS Mail — вход')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Почтовый клиент',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isEas
                        ? 'Exchange ActiveSync 16.1'
                        : 'IMAP / SMTP (Gmail, Яндекс, Mail.ru и др.)',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (kIsWeb)
                    Card(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'В браузере доступен только Exchange (EAS). '
                          'Для IMAP запустите: flutter run -d windows',
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SegmentedButton<MailProtocol>(
                    segments: [
                      const ButtonSegment(
                        value: MailProtocol.eas,
                        label: Text('Exchange'),
                        icon: Icon(Icons.business),
                      ),
                      ButtonSegment(
                        value: MailProtocol.imap,
                        label: const Text('IMAP'),
                        icon: const Icon(Icons.mail_outline),
                        enabled: supportsImapSmtp,
                      ),
                    ],
                    selected: {_protocol},
                    onSelectionChanged: (s) {
                      setState(() {
                        _protocol = s.first;
                        if (_protocol == MailProtocol.imap) {
                          _onEmailChanged();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  if (isEas) ...[
                    SegmentedButton<EasAuthType>(
                      segments: const [
                        ButtonSegment(
                          value: EasAuthType.basic,
                          label: Text('Пароль'),
                          icon: Icon(Icons.key),
                        ),
                        ButtonSegment(
                          value: EasAuthType.oauth,
                          label: Text('Microsoft 365'),
                          icon: Icon(Icons.cloud),
                        ),
                      ],
                      selected: {_authType},
                      onSelectionChanged: (s) => setState(() => _authType = s.first),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (isOAuth && !OAuthConfig.isConfigured)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Укажите Client ID в lib/config/oauth_config.dart',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  if (!isOAuth) ...[
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Укажите email' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        helperText: isEas
                            ? null
                            : 'Для Gmail используйте пароль приложения',
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Укажите пароль' : null,
                    ),
                  ],
                  if (isEas && !isOAuth) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _domain,
                      decoration: const InputDecoration(
                        labelText: 'Домен (необязательно)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (isEas) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _server,
                      decoration: InputDecoration(
                        labelText: 'Сервер (необязательно)',
                        hintText: isOAuth ? 'outlook.office365.com' : 'mail.company.ru',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (!isEas) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _imapPresetId,
                      decoration: const InputDecoration(
                        labelText: 'Провайдер',
                        border: OutlineInputBorder(),
                      ),
                      items: ImapPresets.all
                          .map((p) => DropdownMenuItem(value: p.id, child: Text(p.label)))
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() {
                          _imapPresetId = id;
                          final preset = ImapPresets.byId(id);
                          if (preset != null) _applyPreset(preset);
                        });
                      },
                    ),
                    if (isCustomImap || _imapPresetId != ImapPresets.custom.id) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _imapHost,
                        decoration: const InputDecoration(
                          labelText: 'IMAP сервер',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => !isCustomImap || (v != null && v.trim().isNotEmpty)
                            ? null
                            : 'Укажите IMAP сервер',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _imapPort,
                              decoration: const InputDecoration(
                                labelText: 'IMAP порт',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilterChip(
                            label: const Text('SSL'),
                            selected: _imapSsl,
                            onSelected: (v) => setState(() => _imapSsl = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _smtpHost,
                        decoration: const InputDecoration(
                          labelText: 'SMTP сервер',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => !isCustomImap || (v != null && v.trim().isNotEmpty)
                            ? null
                            : 'Укажите SMTP сервер',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _smtpPort,
                              decoration: const InputDecoration(
                                labelText: 'SMTP порт',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilterChip(
                            label: const Text('SSL/TLS'),
                            selected: _smtpSsl,
                            onSelected: (v) => setState(() => _smtpSsl = v),
                          ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(isEas ? 'Autodiscover' : 'Автонастройка IMAP'),
                    subtitle: Text(
                      isEas
                          ? 'Найти URL Exchange ActiveSync'
                          : 'Определить серверы по email (если поддерживается)',
                    ),
                    value: _useAutodiscover,
                    onChanged: (v) => setState(() => _useAutodiscover = v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: session.loading
                        ? null
                        : (isOAuth ? _connectOAuth : _connectBasic),
                    child: session.loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            isOAuth
                                ? 'Войти через Microsoft'
                                : isEas
                                    ? 'Войти (Exchange)'
                                    : 'Войти (IMAP)',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
