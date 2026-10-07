import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/widgets/table_card.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';

void main() {
  testWidgets('TableCard offline state matches idle state for cardBg, border, and table icon, while keeping red dot and offline text', (tester) async {
    final offlineTable = TableModel(
      id: 'table_1',
      tableNumber: 1,
      deviceId: 'dev_1',
      createdAt: 1000,
      status: 'idle',
      flag: -1,
      isDeviceOnline: false, // Offline!
      isUnlocked: true,
    );

    final idleTable = TableModel(
      id: 'table_2',
      tableNumber: 2,
      deviceId: 'dev_2',
      createdAt: 1000,
      status: 'idle',
      flag: -1,
      isDeviceOnline: true, // Online Idle!
      isUnlocked: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.light(surface: Colors.white),
        ),
        home: Scaffold(
          body: Column(
            children: [
              TableCard(table: offlineTable),
              TableCard(table: idleTable),
            ],
          ),
        ),
      ),
    );

    // 1. Verify Offline Text & Icon is displayed
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

    // 2. Verify Idle Text & Icon is displayed
    expect(find.text('IDLE'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);

    // 3. Find AnimatedContainers for both cards
    final containers = tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)).toList();
    expect(containers.length, 2);

    final offlineDeco = containers[0].decoration as BoxDecoration;
    final idleDeco = containers[1].decoration as BoxDecoration;

    // Card Background Color should match idle state (surface color: Colors.white)
    expect(offlineDeco.color, equals(idleDeco.color));
    expect(offlineDeco.color, equals(Colors.white));

    // Card Border Color should match idle state (const Color(0xFFFFB74D) with alpha 0.5)
    final offlineBorder = offlineDeco.border as Border;
    final idleBorder = idleDeco.border as Border;
    expect(offlineBorder.top.color, equals(idleBorder.top.color));
    expect(offlineBorder.top.color, equals(const Color(0xFFFFB74D).withValues(alpha: 0.5)));

    // 4. Verify Table Restaurant Icons have the exact same color (idle orange: Color(0xFFFF9800))
    final tableIcons = tester.widgetList<Icon>(find.byIcon(Icons.table_restaurant_rounded)).toList();
    expect(tableIcons.length, 2);
    expect(tableIcons[0].color, equals(const Color(0xFFFF9800))); // Offline table icon
    expect(tableIcons[1].color, equals(const Color(0xFFFF9800))); // Idle table icon

    // 5. Verify Dot Colors: Offline is Red (0xFFEF4444) and Idle is Green (0xFF22C55E)
    // Find the Tooltips wrapping the status dots
    final offlineTooltip = tester.widget<Tooltip>(find.byWidgetPredicate(
      (w) => w is Tooltip && w.message == 'Device Offline',
    ));
    final idleTooltip = tester.widget<Tooltip>(find.byWidgetPredicate(
      (w) => w is Tooltip && w.message == 'Device Online',
    ));

    final offlineDotContainer = offlineTooltip.child as Container;
    final idleDotContainer = idleTooltip.child as Container;

    final offlineDotDeco = offlineDotContainer.decoration as BoxDecoration;
    final idleDotDeco = idleDotContainer.decoration as BoxDecoration;

    expect(offlineDotDeco.color, equals(const Color(0xFFEF4444))); // Red dot for offline
    expect(idleDotDeco.color, equals(const Color(0xFF22C55E)));   // Green dot for online

    // 6. Verify Offline Text Badge color is slate grey (Color(0xFF64748B))
    final offlineTextWidget = tester.widget<Text>(find.text('OFFLINE'));
    expect(offlineTextWidget.style?.color, equals(const Color(0xFF64748B)));
  });
}
