import 'package:eas_mail/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('приложение открывает экран входа', (tester) async {
    await tester.pumpWidget(const EasMailApp());
    await tester.pump();
    expect(find.text('EAS Mail — вход'), findsOneWidget);
  });
}
