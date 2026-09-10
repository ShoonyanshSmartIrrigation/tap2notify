import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/fcm_service.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Native Notification Bridge Tests', () {
    const channel = MethodChannel('tab2notify/native_notifications');
    final List<MethodCall> methodCalls = [];

    setUp(() {
      methodCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        methodCalls.add(methodCall);
        if (methodCall.method == 'showNotification') {
          return true;
        } else if (methodCall.method == 'getInitialNotificationPayload') {
          return null;
        } else if (methodCall.method == 'clearNotification') {
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('showNativeNotification dispatches correct method call and arguments', () async {
      final fcm = FCMService();
      await fcm.showNativeNotification(
        title: '🛎️ Table 2 Calling!',
        body: 'Customer requested immediate assistance at Table 2 🔴',
        requestId: 'table_2',
        tableNumber: 2,
      );

      expect(methodCalls.length, 1);
      final call = methodCalls.first;
      expect(call.method, 'showNotification');
      expect(call.arguments['title'], '🛎️ Table 2 Calling!');
      expect(call.arguments['body'], 'Customer requested immediate assistance at Table 2 🔴');
      expect(call.arguments['requestId'], 'table_2');
      expect(call.arguments['tableNumber'], 2);
      expect(call.arguments['notificationId'], 2);
    });

    test('clearNativeNotification dispatches clearNotification with correct notificationId', () async {
      final fcm = FCMService();
      await fcm.clearNativeNotification(2);

      expect(methodCalls.length, 1);
      final call = methodCalls.first;
      expect(call.method, 'clearNotification');
      expect(call.arguments['notificationId'], 2);
    });

    test('TableModel correctly detects pending, accepted, and waiter assignment', () {
      final table = TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        status: 'pending',
        flag: 0,
        waiterName: 'Rahul Sharma (W001)',
        assignedWaiterId: 'W001',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(table.isPending, isTrue);
      expect(table.isAccepted, isFalse);
      expect(table.isAssigned, isTrue);
      expect(table.assignedWaiterId, 'W001');
      expect(table.waiterName.contains('W001'), isTrue);
    });
  });
}
