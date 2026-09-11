import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/ble_service.dart';
import 'package:tab2notify/core/services/firebase_realtime_service.dart';
import 'package:tab2notify/core/services/notification_audio_service.dart';
import 'package:tab2notify/features/service_requests/data/service_request_repository.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';

class MockFirebaseRealtimeService extends FirebaseRealtimeService {
  @override
  Stream<List<TableModel>> getTablesStream({
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    return const Stream.empty();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> nativeNotifCalls = [];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('tab2notify/native_notifications'),
      (MethodCall call) async {
        nativeNotifCalls.add(call);
        return true;
      },
    );
  });

  setUp(() {
    nativeNotifCalls.clear();
  });

  group('Waiter Audio Notification & Targeted Routing Tests', () {
    test('Waiter A receives audio & notification for assigned Table 1', () {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      // Active session: Waiter W001
      ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      // Simulate Table 1 (assigned to W001) triggering a request
      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        createdAt: 1700000000000,
      );

      bleService.onDeviceDiscovered?.call(table1);

      // Verify native notification and audio prompt were triggered
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);
      expect(nativeNotifCalls.any((c) => c.method == 'showNotification'), isTrue);
      final showNotif = nativeNotifCalls.firstWhere((c) => c.method == 'showNotification');
      expect(showNotif.arguments['requestId'], 'table_1');
    });

    test('Waiter A suppresses audio & notification for Table 2 (assigned to Waiter B)', () {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      // Active session: Waiter W001
      ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      // Table 2 is assigned to W002
      final table2 = TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W002',
        waiterName: 'Suresh (W002)',
        createdAt: 1700000000000,
      );

      bleService.onDeviceDiscovered?.call(table2);

      // Verify notification and audio were suppressed on Waiter A's session
      expect(nativeNotifCalls, isEmpty);
    });

    test('Unassigned Table 3 request is gracefully suppressed and not sent to arbitrary waiter', () {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      // Table 3 has NO assigned waiter
      final table3 = TableModel(
        id: 'table_3',
        tableNumber: 3,
        deviceId: 'device_3',
        status: 'pending',
        flag: 0,
        assignedWaiterId: '',
        waiterName: '',
        createdAt: 1700000000000,
      );

      bleService.onDeviceDiscovered?.call(table3);

      expect(nativeNotifCalls, isEmpty);
    });

    test('Reassigned table routes audio notification to the newly assigned waiter', () {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W002',
      );

      // Table 1 is reassigned to Waiter B (W002)
      final reassignedTable1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W002',
        waiterName: 'Suresh (W002)',
        createdAt: 1700000000000,
      );

      // When request arrives:
      bleService.onDeviceDiscovered?.call(reassignedTable1);

      // Only repoWaiterB should trigger
      expect(nativeNotifCalls.any((c) => c.method == 'showNotification'), isTrue);
      final showNotif = nativeNotifCalls.firstWhere((c) => c.method == 'showNotification');
      expect(showNotif.arguments['requestId'], 'table_1');
    });

    test('Manager session suppresses table service request audio and notification', () {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      // Manager session: currentWaiterId is empty
      ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: '',
      );

      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        createdAt: 1700000000000,
      );

      bleService.onDeviceDiscovered?.call(table1);

      expect(nativeNotifCalls, isEmpty);
    });

    test('Accepting request stops active audio playback', () async {
      await NotificationAudioService().stop();
      expect(nativeNotifCalls.any((c) => c.method == 'stopAudioPrompt'), isTrue);
    });
  });
}
