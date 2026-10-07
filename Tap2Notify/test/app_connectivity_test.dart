import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/app_connectivity_service.dart';
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

  @override
  Stream<List<TableModel>> getTablesForWaiterStream(
    String waiterId, {
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    return _tablesController.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('tab2notify/native_notifications'),
      (MethodCall call) async => true,
    );
  });

  setUp(() {
    NotificationAudioService().resetForTesting();
    ServiceRequestRepository.resetNotificationStateForTesting();
    AppConnectivityService().resetForTesting();
  });

  tearDown(() {
    AppConnectivityService().resetForTesting();
  });

  group('App Connectivity & Instant Offline Status Detection Tests', () {
    test(
      '1. When app has connectivity, tables reflect their online state',
      () async {
        final bleService = BleService();
        final dbService = MockFirebaseRealtimeService();
        final repo = ServiceRequestRepository(
          bleService,
          dbService,
          managerPhone: '9876543210',
        );

        AppConnectivityService().setConnectivityForTesting(true);

        final now = DateTime.now().millisecondsSinceEpoch;
        final table1 = TableModel(
          id: 'table_1',
          tableNumber: 1,
          deviceId: 'device_1',
          status: 'idle',
          flag: -1,
          isDeviceOnline: true,
          isUnlocked: true,
          createdAt: now,
        );

        final tablesFuture = repo.getTablesStream().first;
        dbService.emitTables([table1]);
        final tables = await tablesFuture;

        expect(tables.length, 1);
        expect(tables.first.isDeviceOnline, isTrue);

        repo.dispose();
      },
    );

    test(
      '2. When app loses connectivity, all devices immediately transition to OFFLINE',
      () async {
        final bleService = BleService();
        final dbService = MockFirebaseRealtimeService();
        final repo = ServiceRequestRepository(
          bleService,
          dbService,
          managerPhone: '9876543210',
        );

        AppConnectivityService().setConnectivityForTesting(true);

        final now = DateTime.now().millisecondsSinceEpoch;
        final table1 = TableModel(
          id: 'table_1',
          tableNumber: 1,
          deviceId: 'device_1',
          status: 'idle',
          flag: -1,
          isDeviceOnline: true,
          isUnlocked: true,
          createdAt: now,
        );
        final table2 = TableModel(
          id: 'table_2',
          tableNumber: 2,
          deviceId: 'device_2',
          status: 'pending',
          flag: 0,
          isDeviceOnline: true,
          isUnlocked: true,
          createdAt: now,
        );

        final emittedLists = <List<TableModel>>[];
        final sub = repo.getTablesStream().listen(emittedLists.add);

        dbService.emitTables([table1, table2]);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(emittedLists.isNotEmpty, isTrue);
        expect(emittedLists.last.every((t) => t.isDeviceOnline), isTrue);

        // Disconnect connectivity (simulating airplane mode / network loss)
        AppConnectivityService().setConnectivityForTesting(false);
        await Future.delayed(const Duration(milliseconds: 50));

        // MUST immediately transition all tables to isDeviceOnline: false
        expect(emittedLists.last.every((t) => !t.isDeviceOnline), isTrue);
        expect(emittedLists.last.length, 2);

        await sub.cancel();
        repo.dispose();
      },
    );

    test(
      '3. When connectivity is restored, online devices immediately update back to ONLINE',
      () async {
        final bleService = BleService();
        final dbService = MockFirebaseRealtimeService();
        final repo = ServiceRequestRepository(
          bleService,
          dbService,
          managerPhone: '9876543210',
        );

        // Start offline
        AppConnectivityService().setConnectivityForTesting(false);

        final now = DateTime.now().millisecondsSinceEpoch;
        final table1 = TableModel(
          id: 'table_1',
          tableNumber: 1,
          deviceId: 'device_1',
          status: 'idle',
          flag: -1,
          isDeviceOnline: true,
          isUnlocked: true,
          createdAt: now,
        );

        final emittedLists = <List<TableModel>>[];
        final sub = repo.getTablesStream().listen(emittedLists.add);

        dbService.emitTables([table1]);
        await Future.delayed(const Duration(milliseconds: 50));

        // When offline, table is forced offline
        expect(emittedLists.last.first.isDeviceOnline, isFalse);

        // Restore connectivity
        AppConnectivityService().setConnectivityForTesting(true);
        await Future.delayed(const Duration(milliseconds: 50));

        // Immediately restored to online
        expect(emittedLists.last.first.isDeviceOnline, isTrue);

        await sub.cancel();
        repo.dispose();
      },
    );

    test(
      '4. Waiter stream: when app has no connectivity, assigned tables immediately show OFFLINE',
      () async {
        final bleService = BleService();
        final dbService = MockFirebaseRealtimeService();
        final repo = ServiceRequestRepository(
          bleService,
          dbService,
          managerPhone: '9876543210',
          currentWaiterId: 'W001',
        );

        AppConnectivityService().setConnectivityForTesting(true);

        final now = DateTime.now().millisecondsSinceEpoch;
        final table1 = TableModel(
          id: 'table_1',
          tableNumber: 1,
          deviceId: 'device_1',
          status: 'idle',
          flag: -1,
          assignedWaiterId: 'W001',
          waiterName: 'Ramesh (W001)',
          isDeviceOnline: true,
          isUnlocked: true,
          createdAt: now,
        );

        final emittedLists = <List<TableModel>>[];
        final sub = repo.getTablesForWaiterStream('W001').listen(emittedLists.add);

        dbService.emitTables([table1]);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(emittedLists.last.first.isDeviceOnline, isTrue);

        // Disconnect connectivity
        AppConnectivityService().setConnectivityForTesting(false);
        await Future.delayed(const Duration(milliseconds: 50));

        // Waiter view immediately shows OFFLINE
        expect(emittedLists.last.first.isDeviceOnline, isFalse);

        // Reconnect
        AppConnectivityService().setConnectivityForTesting(true);
        await Future.delayed(const Duration(milliseconds: 50));

        // Restored
        expect(emittedLists.last.first.isDeviceOnline, isTrue);

        await sub.cancel();
        repo.dispose();
      },
    );
  });
}
