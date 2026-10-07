import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/widgets/custom_bottom_navbar.dart';

void main() {
  group('CustomBottomNavBar SafeArea and Inset Tests', () {
    testWidgets('Renders SafeArea with 48.0 bottom inset (Android 3-button navigation)', (tester) async {
      int tappedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            splashFactory: InkRipple.splashFactory,
          ),
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 48.0),
              viewPadding: EdgeInsets.only(bottom: 48.0),
            ),
            child: Scaffold(
              bottomNavigationBar: CustomBottomNavBar(
                currentIndex: 0,
                pendingCount: 3,
                onTap: (idx) => tappedIndex = idx,
              ),
            ),
          ),
        ),
      );

      // Verify SafeArea is present and wraps the navigation container
      final safeAreaFinder = find.byType(SafeArea);
      expect(safeAreaFinder, findsOneWidget);

      final safeAreaWidget = tester.widget<SafeArea>(safeAreaFinder);
      expect(safeAreaWidget.top, isFalse);
      expect(safeAreaWidget.bottom, isTrue);

      // Verify navigation items exist and are visible
      expect(find.text('Tables'), findsOneWidget);
      expect(find.byIcon(Icons.table_restaurant_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bar_chart_rounded), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);

      // Verify pending badge count '3' is rendered
      expect(find.text('3'), findsOneWidget);

      // Test tapping Overview tab (index 1)
      await tester.tap(find.byIcon(Icons.bar_chart_rounded));
      await tester.pumpAndSettle();
      expect(tappedIndex, 1);

      // Test tapping Settings tab (index 2)
      await tester.tap(find.byIcon(Icons.person_rounded));
      await tester.pumpAndSettle();
      expect(tappedIndex, 2);

      // Verify bottom margin reflects safe area padding
      final safeAreaBox = tester.getRect(safeAreaFinder);
      final containerFinder = find.descendant(
        of: safeAreaFinder,
        matching: find.byType(Container).first,
      );
      final containerBox = tester.getRect(containerFinder);

      // The container inside SafeArea starts above the 48dp inset
      expect(safeAreaBox.bottom - containerBox.bottom, equals(48.0));
    });

    testWidgets('Renders without extra padding when bottom inset is 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            splashFactory: InkRipple.splashFactory,
          ),
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
            ),
            child: Scaffold(
              bottomNavigationBar: CustomBottomNavBar(
                currentIndex: 1,
                pendingCount: 0,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );

      final safeAreaFinder = find.byType(SafeArea);
      expect(safeAreaFinder, findsOneWidget);

      final safeAreaBox = tester.getRect(safeAreaFinder);
      final containerFinder = find.descendant(
        of: safeAreaFinder,
        matching: find.byType(Container).first,
      );
      final containerBox = tester.getRect(containerFinder);

      // No extra bottom padding introduced when inset is 0
      expect(safeAreaBox.bottom - containerBox.bottom, equals(0.0));
      expect(find.text('Overview'), findsOneWidget);
    });

    testWidgets('Renders correctly with 20.0 bottom inset (Android Gesture Navigation)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            splashFactory: InkRipple.splashFactory,
          ),
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 20.0),
              viewPadding: EdgeInsets.only(bottom: 20.0),
            ),
            child: Scaffold(
              bottomNavigationBar: CustomBottomNavBar(
                currentIndex: 2,
                pendingCount: 0,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );

      final safeAreaFinder = find.byType(SafeArea);
      final safeAreaBox = tester.getRect(safeAreaFinder);
      final containerFinder = find.descendant(
        of: safeAreaFinder,
        matching: find.byType(Container).first,
      );
      final containerBox = tester.getRect(containerFinder);

      // Lifted exactly by the 20.0dp gesture inset
      expect(safeAreaBox.bottom - containerBox.bottom, equals(20.0));
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
