import 'package:eas_mail/eas/mime_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MIME без вложений', () {
    final mime = MimeBuilder.build(
      from: 'a@b.com',
      to: 'c@d.com',
      subject: 'Test',
      body: 'Hello',
    );
    expect(mime, contains('From: a@b.com'));
    expect(mime, contains('Hello'));
  });
}
