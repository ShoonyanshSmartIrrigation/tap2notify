import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tab2notify/core/services/shared_preferences_provider.dart';
import 'package:tab2notify/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const Tab2NotifyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Tab2Notify'), findsWidgets);
    // Flush splash screen 2-second navigation timer
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
