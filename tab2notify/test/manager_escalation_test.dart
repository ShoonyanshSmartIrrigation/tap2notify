import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/ble_service.dart';
import 'package:tab2notify/core/services/firebase_realtime_service.dart';
import 'package:tab2notify/core/services/notification_audio_service.dart';
import 'package:tab2notify/features/service_requests/data/service_request_repository.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';

class MockFirebaseRealtimeService extends FirebaseRealtimeService {
  final StreamController<List<TableModel>> _tablesController =
      StreamController<List<TableModel>>.broadcast();

  void emitTables(List<TableModel> tables) {
    _tablesController.add(tables);
  }

  @override
  Stream<List<TableModel>> getTablesStream({
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    return _tablesController.stream;
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
    NotificationAudioService().resetForTesting();
  });

  group('20-Second Manager Escalation & Audio Alert Tests', () {
    test('1. Waiter receives immediate alert for assigned table; Manager receives 0 alerts immediately', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      // Waiter W001 session
      final repoWaiter = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        createdAt: now,
        requestSentAt: now,
      );

      dbService.emitTables([table1]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Waiter received immediate incoming prompt
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isFalse);

      repoWaiter.dispose();
    });

    test('2. Manager receives escalation alert & Please_Hold audio when table remains pending > 20s', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      // Manager session (currentWaiterId is empty)
      final repoManager = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: '',
      );

      // Table requested 25 seconds ago (elapsed > 20000ms)
      final sentTime = DateTime.now().millisecondsSinceEpoch - 25000;
      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        createdAt: sentTime,
        requestSentAt: sentTime,
      );

      dbService.emitTables([table1]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Manager received Please_Hold audio and escalation notification
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isTrue);
      final showNotifs = nativeNotifCalls.where((c) => c.method == 'showNotification').toList();
      expect(showNotifs.isNotEmpty, isTrue);
      final escalationNotif = showNotifs.last;
      expect(escalationNotif.arguments['title'], contains('Unattended Table 1 Alert'));
      expect(escalationNotif.arguments['channelId'], 'manager_escalation_channel');
      expect(escalationNotif.arguments['sound'], 'please_hold');

      repoManager.dispose();
    });

    test('3. If table is accepted within 20s, manager escalation is suppressed', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      // Manager session
      final repoManager = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: '',
      );

      // Table requested 5 seconds ago and was accepted by Waiter
      final sentTime = DateTime.now().millisecondsSinceEpoch - 5000;
      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'accepted',
        flag: 1,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        createdAt: sentTime,
        requestSentAt: sentTime,
        acceptedAt: sentTime + 2000,
      );

      dbService.emitTables([table1]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Result: 0 manager audio prompts, 0 manager escalation notifications
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isFalse);
      expect(nativeNotifCalls.where((c) => c.method == 'showNotification').isEmpty, isTrue);

      repoManager.dispose();
    });

    test('4. If table is reset/idle within 20s, manager escalation is suppressed', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      // Manager session
      final repoManager = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: '',
      );

      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'idle',
        flag: -1,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      dbService.emitTables([table1]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Result: 0 manager audio prompts
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isFalse);
      expect(nativeNotifCalls.where((c) => c.method == 'showNotification').isEmpty, isTrue);

      repoManager.dispose();
    });

    test('5. Idempotency: Multiple checks for same pending table trigger Please_Hold only once', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      final repoManager = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: '',
      );

      final sentTime = DateTime.now().millisecondsSinceEpoch - 30000;
      final table5 = TableModel(
        id: 'table_5',
        tableNumber: 5,
        deviceId: 'device_5',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        createdAt: sentTime,
        requestSentAt: sentTime,
      );

      // Emit multiple times in succession
      dbService.emitTables([table5]);
      await Future.delayed(const Duration(milliseconds: 20));
      dbService.emitTables([table5]);
      await Future.delayed(const Duration(milliseconds: 20));
      dbService.emitTables([table5]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Result: Exactly 1 manager escalation call
      final managerAudioCalls = nativeNotifCalls.where((c) => c.method == 'playManagerAudioPrompt').toList();
      expect(managerAudioCalls.length, 1);

      repoManager.dispose();
    });

    test('6. Manager receives ZERO immediate alerts when table without requestSentAt becomes pending (even if createdAt is 3 days old)', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      final repoManager = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: '',
      );

      // Table was created 3 days ago in database, and ESP32 sets flag=0 without requestSentAt
      final threeDaysAgo = DateTime.now().millisecondsSinceEpoch - 259200000;
      final table6 = TableModel(
        id: 'table_6',
        tableNumber: 6,
        deviceId: 'device_6',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        createdAt: threeDaysAgo,
        // requestSentAt is null
      );

      dbService.emitTables([table6]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Result at t = 0s: 0 manager alerts, 0 Please_Hold audio
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isFalse,
          reason: 'Manager must NEVER receive Please_Hold audio immediately at 0s');
      expect(nativeNotifCalls.where((c) => c.method == 'showNotification').isEmpty, isTrue,
          reason: 'Manager must NEVER receive notification immediately at 0s');

      repoManager.dispose();
    });
  });
}
