import 'package:eas_mail/eas/wbxml/code_pages.dart';
import 'package:eas_mail/eas/wbxml/wbxml_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WBXML roundtrip Provision', () {
    final original = WbXmlCodec.element(
      EasCodePages.provision,
      'Provision',
      children: [
        WbXmlCodec.element(
          EasCodePages.provision,
          'Policies',
          children: [
            WbXmlCodec.element(
              EasCodePages.provision,
              'Policy',
              children: [
                WbXmlCodec.element(
                  EasCodePages.provision,
                  'PolicyType',
                  text: 'MS-EAS-Provisioning-WBXML',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final bytes = WbXmlCodec.encode(original);
    final decoded = WbXmlCodec.decode(bytes);
    expect(decoded.name, 'Provision');
    expect(
      decoded.child('Policies')?.child('Policy')?.childText('PolicyType'),
      'MS-EAS-Provisioning-WBXML',
    );
  });
}
