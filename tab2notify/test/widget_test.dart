import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: Tab2NotifyApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Tab2Notify'), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
  });
}
