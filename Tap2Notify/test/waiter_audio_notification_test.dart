import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/ble_service.dart';
import 'package:tab2notify/core/services/firebase_realtime_service.dart';
import 'package:tab2notify/core/services/notification_audio_service.dart';
import 'package:tab2notify/features/service_requests/data/service_request_repository.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';

class MockFirebaseRealtimeService extends FirebaseRealtimeService {
  final StreamController<List<TableModel>>? streamController;

  MockFirebaseRealtimeService({this.streamController});

  @override
  Stream<List<TableModel>> getTablesStream({
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    return streamController?.stream ?? const Stream.empty();
  }

  @override
  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? waiterId,
    String? managerPhone,
    String? managerUid,
  }) async {}

  @override
  Future<void> resetTableStatus(String tableId, {String? managerPhone}) async {}
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
    ServiceRequestRepository.resetNotificationStateForTesting();
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

      // Simulate Table 1 (assigned to W001 and unlocked) triggering a request
      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
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
        isUnlocked: true,
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
        isUnlocked: true,
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
        isUnlocked: true,
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
        isUnlocked: true,
        createdAt: 1700000000000,
      );

      bleService.onDeviceDiscovered?.call(table1);

      expect(nativeNotifCalls, isEmpty);
    });

    test('Accepting request stops active audio playback', () async {
      await NotificationAudioService().stop();
      expect(nativeNotifCalls.any((c) => c.method == 'stopAudioPrompt'), isTrue);
    });

    test('When two tables are pending and Table 1 is accepted, audio does NOT re-trigger for Table 2', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      final repo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: 1700000000000,
        requestSentAt: 1700000000000,
      );

      final table2 = TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: 1700000005000,
        requestSentAt: 1700000005000,
      );

      // Table 1 becomes pending -> audio played for Table 1
      bleService.onDeviceDiscovered?.call(table1);
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);

      // Clear calls and reset audio debounce to simulate separate device arrival
      nativeNotifCalls.clear();
      NotificationAudioService().resetForTesting();

      // Table 2 becomes pending -> audio played for Table 2
      bleService.onDeviceDiscovered?.call(table2);
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);

      // Waiter accepts Table 1
      nativeNotifCalls.clear();
      NotificationAudioService().resetForTesting(); // Even if debounce window elapsed
      await repo.acceptTableRequest(tableId: 'table_1', waiterName: 'Ramesh');

      // Now Table 1 is accepted, Table 2 remains pending.
      // Hardware/poll/cloud delivers an update with Table 2 still in pending state
      nativeNotifCalls.clear();
      bleService.onDeviceDiscovered?.call(table2);

      // Verify that sound did NOT re-trigger for Table 2!
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isFalse);
      expect(nativeNotifCalls.any((c) => c.method == 'showNotification'), isFalse);
    });

    test('Genuinely new pending request triggers audio after previous request was accepted', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      final repo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: 1700000000000,
      );

      // 1st request on Table 1
      bleService.onDeviceDiscovered?.call(table1);
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);

      // Waiter accepts Table 1
      await repo.acceptTableRequest(tableId: 'table_1', waiterName: 'Ramesh');

      // Clear calls and reset audio debounce
      nativeNotifCalls.clear();
      NotificationAudioService().resetForTesting();

      // Later, customer at Table 1 presses button again -> genuinely new request!
      final newTable1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: 1700000050000,
        requestSentAt: 1700000050000,
      );

      bleService.onDeviceDiscovered?.call(newTable1);

      // Audio prompt MUST play for this genuinely new request!
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);
      expect(nativeNotifCalls.any((c) => c.method == 'showNotification'), isTrue);
    });

    test('Cloud stream: accepting Table 1 does NOT re-trigger audio for remaining pending Table 2', () async {
      final bleService = BleService();
      final streamController = StreamController<List<TableModel>>.broadcast();
      final dbService = MockFirebaseRealtimeService(streamController: streamController);

      final repo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: 1700000000000,
        requestSentAt: 1700000000000,
      );

      final table2 = TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: 1700000005000,
        requestSentAt: 1700000005000,
      );

      // Cloud delivers both tables pending
      streamController.add([table1, table2]);
      await pumpEventQueue();

      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);

      // Waiter accepts Table 1
      nativeNotifCalls.clear();
      NotificationAudioService().resetForTesting(); // Even if time elapsed
      await repo.acceptTableRequest(tableId: 'table_1', waiterName: 'Ramesh');

      // Cloud emits updated tables: Table 1 is accepted, Table 2 is still pending
      nativeNotifCalls.clear();
      final acceptedTable1 = table1.copyWith(
        status: 'accepted',
        flag: 1,
        acceptedAt: 1700000010000,
      );
      streamController.add([acceptedTable1, table2]);
      await pumpEventQueue();

      // Sound MUST NOT play again for Table 2!
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isFalse);
      expect(nativeNotifCalls.any((c) => c.method == 'showNotification'), isFalse);

      await streamController.close();
    });

    test('Pull-to-refresh: re-fetching gateway devices or invalidating stream does NOT re-trigger sound for pending table', () async {
      final bleService = BleService();
      final streamController = StreamController<List<TableModel>>.broadcast();
      final dbService = MockFirebaseRealtimeService(streamController: streamController);

      final repo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: 1700000000000,
        requestSentAt: 1700000000000,
      );

      // Table 1 becomes pending and notifies
      streamController.add([table1]);
      await pumpEventQueue();

      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);

      // Reset audio debounce and native calls to simulate elapsed time
      nativeNotifCalls.clear();
      NotificationAudioService().resetForTesting();

      // User pulls RefreshIndicator: gateway devices refreshed & stream re-emits
      bleService.processDevicePayloadForTesting({
        'id': '1',
        'tableNumber': '1',
        'flag': 0,
        'status': 'pending',
        'online': true,
        'unlocked': true,
        'verified': true,
        'assigned_waiter_id': 'W001',
        'waiterName': 'Ramesh (W001)',
      });
      streamController.add([table1]);
      await pumpEventQueue();

      // Even if a new ServiceRequestRepository instance was created during refresh:
      final refreshedRepo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );
      streamController.add([table1]);
      await pumpEventQueue();

      // Sound MUST NOT play again on refresh!
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isFalse);
      expect(nativeNotifCalls.any((c) => c.method == 'showNotification'), isFalse);

      await streamController.close();
      refreshedRepo.dispose();
      repo.dispose();
    });

    test('Two pending tables: accepting Table 1 does NOT re-trigger audio for Table 2 even with cloud timestamp jitter', () async {
      final bleService = BleService();
      final streamController = StreamController<List<TableModel>>.broadcast();
      final dbService = MockFirebaseRealtimeService(streamController: streamController);

      final repo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: 1700000000000,
        requestSentAt: 1700000000000,
      );

      final table2 = TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: 1700000005000,
        requestSentAt: 1700000005000,
      );

      // Cloud delivers both tables pending initially
      streamController.add([table1, table2]);
      await pumpEventQueue();

      // Audio prompt played
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);

      // Clear calls and reset audio debounce
      nativeNotifCalls.clear();
      NotificationAudioService().resetForTesting();

      // Waiter accepts Table 1
      await repo.acceptTableRequest(tableId: 'table_1', waiterName: 'Ramesh');

      // Cloud stream emits updated list: Table 1 is accepted, Table 2 has updated/jittered timestamp (+50ms)
      nativeNotifCalls.clear();
      final acceptedTable1 = table1.copyWith(
        status: 'accepted',
        flag: 1,
        acceptedAt: 1700000010000,
      );
      final jitteredTable2 = table2.copyWith(
        requestSentAt: 1700000005050, // Slight clock skew or RTDB async write
        updatedAt: 1700000010000,
      );
      streamController.add([acceptedTable1, jitteredTable2]);
      await pumpEventQueue();

      // Table 2 MUST NOT play sound or show notification!
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isFalse);
      expect(nativeNotifCalls.any((c) => c.method == 'showNotification'), isFalse);

      await streamController.close();
      repo.dispose();
    });
  });
}

