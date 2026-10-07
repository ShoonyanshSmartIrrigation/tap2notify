import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/ble_service.dart';
import 'package:tab2notify/core/services/fcm_service.dart';
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
    FCMService().resetForTesting();
    ServiceRequestRepository.resetNotificationStateForTesting();
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
        isUnlocked: true,
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
        isUnlocked: true,
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
        isUnlocked: true,
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
        isUnlocked: true,
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
        isUnlocked: true,
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
        isUnlocked: true,
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

    test('7. Waiter session strictly suppresses Please_Hold audio and manager escalation notification even after 25s pending', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeService();

      // Configure active Waiter session
      FCMService().setSessionForTesting(
        userId: 'W001',
        role: 'waiter',
        managerPhone: '9876543210',
      );

      final repoWaiter = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      // Table requested 25 seconds ago (elapsed > 20000ms)
      final sentTime = DateTime.now().millisecondsSinceEpoch - 25000;
      final table7 = TableModel(
        id: 'table_7',
        tableNumber: 7,
        deviceId: 'device_7',
        status: 'pending',
        flag: 0,
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: sentTime,
        requestSentAt: sentTime,
      );

      dbService.emitTables([table7]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Waiter must NEVER receive Please_Hold audio prompt
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isFalse,
          reason: 'Please_Hold audio must NEVER play on Waiter side');

      // Any notifications sent must NEVER use manager_escalation_channel or please_hold sound
      final showNotifs = nativeNotifCalls.where((c) => c.method == 'showNotification').toList();
      for (final notif in showNotifs) {
        expect(notif.arguments['channelId'], isNot('manager_escalation_channel'),
            reason: 'Manager escalation channel must NEVER be used on Waiter side');
        expect(notif.arguments['sound'], isNot('please_hold'),
            reason: 'please_hold sound must NEVER be used on Waiter side');
      }

      repoWaiter.dispose();
    });

    test('8. NotificationAudioService.playManagerEscalationPrompt explicitly suppresses Please_Hold when role is waiter', () async {
      // 1. Explicit waiter role param
      await NotificationAudioService().playManagerEscalationPrompt(
        tableId: 'table_8',
        role: 'waiter',
      );
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isFalse,
          reason: 'playManagerEscalationPrompt must abort when role is waiter');

      // 2. Active role set to waiter
      NotificationAudioService().setActiveRole('waiter');
      await NotificationAudioService().playManagerEscalationPrompt(
        tableId: 'table_8',
      );
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isFalse,
          reason: 'playManagerEscalationPrompt must abort when activeRole is waiter');

      // 3. Manager role allowed
      NotificationAudioService().setActiveRole('manager');
      await NotificationAudioService().playManagerEscalationPrompt(
        tableId: 'table_8',
        role: 'manager',
      );
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isTrue,
          reason: 'playManagerEscalationPrompt must play for manager role');
    });

    test('9. FCMService rejects manager escalation payload on Waiter device but accepts on Manager device', () {
      // Configure Waiter session
      FCMService().setSessionForTesting(
        userId: 'W001',
        role: 'waiter',
        managerPhone: '9876543210',
      );

      const escalationMessage = RemoteMessage(
        data: {
          'type': 'manager_escalation',
          'channelId': 'manager_escalation_channel',
          'sound': 'please_hold',
          'targetRole': 'manager',
          'requestId': 'table_9',
        },
      );

      // Must be rejected on Waiter device
      final isAuthorizedWaiter = FCMService().isMessageAuthorizedForCurrentSessionForTesting(escalationMessage);
      expect(isAuthorizedWaiter, isFalse,
          reason: 'Manager escalation push must be rejected on Waiter session');

      // Configure Manager session
      FCMService().setSessionForTesting(
        userId: 'M001',
        role: 'manager',
        managerPhone: '9876543210',
      );

      final isAuthorizedManager = FCMService().isMessageAuthorizedForCurrentSessionForTesting(escalationMessage);
      expect(isAuthorizedManager, isTrue,
          reason: 'Manager escalation push must be authorized on Manager session');
    });

    test('10. FCMService foreground message handler completely suppresses manager escalation / Please_Hold on Waiter device', () {
      // Configure Waiter session
      FCMService().setSessionForTesting(
        userId: 'W001',
        role: 'waiter',
        managerPhone: '9876543210',
      );

      const escalationMessage = RemoteMessage(
        data: {
          'type': 'manager_escalation',
          'sound': 'please_hold',
          'channelId': 'manager_escalation_channel',
          'requestId': 'table_10',
        },
      );

      FCMService().handleForegroundMessageForTesting(escalationMessage);

      // Must produce zero native audio calls and zero notifications on Waiter side
      expect(nativeNotifCalls.isEmpty, isTrue,
          reason: 'Foreground escalation message must be completely silent and suppressed on Waiter side');

      // Now switch to Manager session
      FCMService().setSessionForTesting(
        userId: 'M001',
        role: 'manager',
        managerPhone: '9876543210',
      );

      FCMService().handleForegroundMessageForTesting(escalationMessage);

      // Manager must receive Please_Hold audio
      expect(nativeNotifCalls.any((c) => c.method == 'playManagerAudioPrompt'), isTrue,
          reason: 'Manager must receive Please_Hold audio on foreground escalation message');
    });

    test('11. FCMService.showNativeNotification strictly suppresses Please_Hold and manager_escalation_channel on Waiter device', () async {
      // Configure Waiter session
      FCMService().setSessionForTesting(
        userId: 'W001',
        role: 'waiter',
        managerPhone: '9876543210',
      );

      await FCMService().showNativeNotification(
        title: '⚠️ Unattended Table 11 Alert!',
        body: 'Table 11 has been pending for >20s!',
        requestId: 'table_11',
        channelId: 'manager_escalation_channel',
        sound: 'please_hold',
      );

      expect(nativeNotifCalls.isEmpty, isTrue,
          reason: 'showNativeNotification must be suppressed on Waiter device when channel/sound is manager escalation');

      // Switch to Manager session
      FCMService().setSessionForTesting(
        userId: 'M001',
        role: 'manager',
        managerPhone: '9876543210',
      );

      await FCMService().showNativeNotification(
        title: '⚠️ Unattended Table 11 Alert!',
        body: 'Table 11 has been pending for >20s!',
        requestId: 'table_11',
        channelId: 'manager_escalation_channel',
        sound: 'please_hold',
      );

      final showNotifs = nativeNotifCalls.where((c) => c.method == 'showNotification').toList();
      expect(showNotifs.length, 1,
          reason: 'showNativeNotification must dispatch on Manager device');
      expect(showNotifs.first.arguments['channelId'], 'manager_escalation_channel');
      expect(showNotifs.first.arguments['sound'], 'please_hold');
      expect(showNotifs.first.arguments['role'], 'manager');
    });
  });
}
