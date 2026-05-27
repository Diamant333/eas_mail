import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:provider/provider.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../../eas/mime_builder.dart';
import '../../mail/models/mail_message.dart';
import '../../services/mail_session.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    this.embedded = false,
    this.replyTo,
    this.forwardOf,
    this.prefilledTo,
    this.initialHtml,
    this.readOnly = false,
  });

  final bool embedded;
  final MailMessage? replyTo;
  final MailMessage? forwardOf;
  final String? prefilledTo;
  /// Pre-populate the editor with this HTML (e.g. for signature editing).
  final String? initialHtml;
  /// If true, the editor is read-only (e.g. preview mode).
  final bool readOnly;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _to;
  late final TextEditingController _subject;
  // Initialised in didChangeDependencies (before first build).
  late quill.QuillController _quill;
  bool _quillReady = false;
  final List<MimeAttachment> _attachments = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();

    final reply = widget.replyTo;
    final fwd = widget.forwardOf;

    _to = TextEditingController(
      text: reply != null ? _extractEmail(reply.from) : (widget.prefilledTo ?? ''),
    );
    _subject = TextEditingController(
      text: reply != null
          ? 'Re: ${reply.subject}'
          : fwd != null
              ? 'Fwd: ${fwd.subject}'
              : '',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_quillReady) return; // only initialise once
    _quillReady = true;

    final reply = widget.replyTo;
    final fwd = widget.forwardOf;

    // Build the initial HTML for the editor.
    // context.read is safe here: the element is fully active when
    // didChangeDependencies() runs (unlike initState).
    String initHtml;
    if (widget.initialHtml != null) {
      initHtml = widget.initialHtml!;
    } else if (reply != null) {
      final session = context.read<MailSession>();
      final sig = session.account?.signatureOnReply == true
          ? session.account!.signature
          : '';
      final quoted = _quoteHtml(reply);
      initHtml = '<p></p>${sig.isNotEmpty ? sig : ''}<hr>$quoted';
    } else if (fwd != null) {
      final session = context.read<MailSession>();
      final sig = session.account?.signatureOnForward == true
          ? session.account!.signature
          : '';
      final quoted = _quoteHtml(fwd);
      initHtml = '<p></p>${sig.isNotEmpty ? sig : ''}<hr>$quoted';
    } else {
      final session = context.read<MailSession>();
      final sig = session.account?.signatureOnCompose == true
          ? session.account!.signature
          : '';
      initHtml = '<p></p>${sig.isNotEmpty ? sig : '<p>С уважением</p>'}';
    }

    // Assign once — no placeholder to dispose.
    _quill = _htmlToController(initHtml);
  }

  quill.QuillController _htmlToController(String html) {
    if (html.trim().isEmpty) {
      return quill.QuillController.basic();
    }
    try {
      final delta = HtmlToDelta().convert(html);
      final doc = quill.Document.fromDelta(delta);
      return quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      return quill.QuillController.basic();
    }
  }

  String _controllerToHtml() {
    final delta = _quill.document.toDelta();
    final converter = QuillDeltaToHtmlConverter(
      delta.toJson().cast<Map<String, dynamic>>(),
      ConverterOptions.forEmail(),
    );
    return converter.convert();
  }

  String _extractEmail(String from) {
    final match = RegExp(r'<([^>]+)>').firstMatch(from);
    return match?.group(1) ?? from.trim();
  }

  String _quoteHtml(MailMessage msg) {
    final date = msg.dateReceived != null
        ? msg.dateReceived!.toLocal().toString().substring(0, 16)
        : '';
    final header = '<p><b>${msg.from}</b> $date:</p>';
    final body = msg.hasHtmlBody
        ? msg.bodyHtml!
        : '<pre>${(msg.body ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</pre>';
    return '$header<blockquote style="border-left:3px solid #ccc;padding-left:12px">$body</blockquote>';
  }

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    if (_quillReady) _quill.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;

    for (final file in result.files) {
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) continue;
      _attachments.add(
        MimeAttachment(
          filename: file.name,
          bytes: bytes,
          contentType: _guessContentType(file.extension),
        ),
      );
    }
    setState(() {});
  }

  Future<void> _pickAndInsertImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) return;

    // Embed the image as a base64 data-URI in the Quill document.
    final mime = _guessContentType(file.extension);
    final base64 = _base64Encode(bytes);
    final dataUri = 'data:$mime;base64,$base64';
    final index = _quill.selection.baseOffset;
    _quill.document.insert(index, quill.BlockEmbed.image(dataUri));
    setState(() {});
  }

  String _base64Encode(Uint8List bytes) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final buf = StringBuffer();
    int i = 0;
    while (i < bytes.length) {
      final b0 = bytes[i++];
      final b1 = i < bytes.length ? bytes[i++] : 0;
      final b2 = i < bytes.length ? bytes[i++] : 0;
      buf.write(chars[b0 >> 2]);
      buf.write(chars[((b0 & 3) << 4) | (b1 >> 4)]);
      buf.write(chars[((b1 & 0xF) << 2) | (b2 >> 6)]);
      buf.write(chars[b2 & 0x3F]);
    }
    final result = buf.toString();
    final pad = bytes.length % 3;
    if (pad == 1) return '${result.substring(0, result.length - 2)}==';
    if (pad == 2) return '${result.substring(0, result.length - 1)}=';
    return result;
  }

  String _guessContentType(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _sending = true);
    final session = context.read<MailSession>();

    try {
      final html = _controllerToHtml();
      await session.sendMail(
        to: _to.text.trim(),
        subject: _subject.text.trim(),
        bodyHtml: html,
        attachments: _attachments.isEmpty ? null : List.of(_attachments),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Письмо отправлено')),
      );
      if (widget.embedded) {
        _to.clear();
        _subject.clear();
        _quill.clear();
        setState(() => _attachments.clear());
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Form(
      key: _formKey,
      child: Column(
        children: [
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  TextFormField(
                    controller: _to,
                    decoration: const InputDecoration(
                      labelText: 'Кому',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Укажите получателя' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _subject,
                    decoration: const InputDecoration(
                      labelText: 'Тема',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          // ── Quill toolbar ──────────────────────────────────────────────────
          if (!widget.readOnly)
            quill.QuillSimpleToolbar(
              controller: _quill,
              config: quill.QuillSimpleToolbarConfig(
                showFontFamily: false,
                showFontSize: false,
                showInlineCode: false,
                showCodeBlock: false,
                showSubscript: false,
                showSuperscript: false,
                showSmallButton: false,
                showSearchButton: false,
                customButtons: [
                  quill.QuillToolbarCustomButtonOptions(
                    icon: const Icon(Icons.image_outlined, size: 18),
                    tooltip: 'Вставить картинку',
                    onPressed: _pickAndInsertImage,
                  ),
                  quill.QuillToolbarCustomButtonOptions(
                    icon: const Icon(Icons.attach_file, size: 18),
                    tooltip: 'Прикрепить файл',
                    onPressed: _pickFiles,
                  ),
                ],
              ),
            ),
          // ── Quill editor ───────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: quill.QuillEditor.basic(
                  controller: _quill,
                  config: quill.QuillEditorConfig(
                    padding: const EdgeInsets.all(12),
                    placeholder: 'Введите текст...',
                    scrollable: true,
                    expands: true,
                  ),
                ),
              ),
            ),
          ),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, size: 16),
                  const SizedBox(width: 4),
                  Text('Вложений: ${_attachments.length}'),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _attachments.clear()),
                    child: const Text('Очистить'),
                  ),
                ],
              ),
            ),
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Отправить'),
              ),
            ),
        ],
      ),
    );

    if (widget.embedded) return body;

    final title = widget.replyTo != null
        ? 'Ответить'
        : widget.forwardOf != null
            ? 'Переслать'
            : widget.readOnly
                ? 'Просмотр'
                : 'Новое письмо';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}
