import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/ble_service.dart';
import 'package:tab2notify/core/services/firebase_realtime_service.dart';
import 'package:tab2notify/core/services/notification_audio_service.dart';
import 'package:tab2notify/features/service_requests/data/service_request_repository.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';
import 'package:tab2notify/features/waiter/domain/waiter_model.dart';

class MockFirebaseRealtimeServiceForRetention extends FirebaseRealtimeService {
  final Map<String, TableModel> _tablesStore = {};
  final Map<String, WaiterModel> _waitersStore = {};

  final StreamController<List<TableModel>> _tablesController =
      StreamController<List<TableModel>>.broadcast();

  void seedTable(TableModel table) {
    _tablesStore[table.id] = table;
    _emitTables();
  }

  void seedWaiter(WaiterModel waiter) {
    _waitersStore[waiter.waiterId] = waiter;
  }

  void _emitTables() {
    _tablesController.add(_tablesStore.values.toList());
  }

  Stream<List<TableModel>> _buildStream() {
    late StreamController<List<TableModel>> controller;
    StreamSubscription<List<TableModel>>? sub;
    controller = StreamController<List<TableModel>>.broadcast(
      onListen: () {
        controller.add(_tablesStore.values.toList());
        sub = _tablesController.stream.listen(
          (data) => controller.add(data),
          onError: (err) => controller.addError(err),
        );
      },
      onCancel: () {
        sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<TableModel>> getTablesStream({
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    return _buildStream();
  }

  @override
  Stream<List<TableModel>> getTablesForWaiterStream(
    String waiterId, {
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    return _buildStream().map((allTables) {
      final waiter = _waitersStore[waiterId];
      final waiterAssignedList = waiter?.assignedTableIds ?? [];

      return allTables.where((t) {
        final isDirect = t.assignedWaiterId == waiterId ||
            t.waiterName == waiterId ||
            t.waiterName.contains('($waiterId)') ||
            t.waiterName.contains(waiterId);
        final isViaList = waiterAssignedList.contains(t.id) ||
            waiterAssignedList.contains(t.tableNumber.toString());
        return isDirect || isViaList;
      }).map((t) {
        return t.copyWith(
          assignedWaiterId: t.assignedWaiterId.isNotEmpty ? t.assignedWaiterId : waiterId,
          isUnlocked: true,
        );
      }).toList();
    });
  }

  @override
  Future<void> assignWaiterToTables({
    required String waiterId,
    required String waiterName,
    required List<String> tableIds,
    String? managerPhone,
  }) async {
    for (final tableId in tableIds) {
      final existing = _tablesStore[tableId];
      if (existing != null) {
        _tablesStore[tableId] = existing.copyWith(
          assignedWaiterId: waiterId,
          waiterName: waiterName,
          isUnlocked: true,
        );
      } else {
        _tablesStore[tableId] = TableModel(
          id: tableId,
          tableNumber: int.tryParse(tableId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1,
          deviceId: 'device_$tableId',
          assignedWaiterId: waiterId,
          waiterName: waiterName,
          isUnlocked: true,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }
    _emitTables();
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
    BleService().resetForTesting();
  });

  group('Waiter Device Retention & Automatic Fetching Across Sessions', () {
    test('1. Manager assigns device to Waiter -> Assignment is saved and delivered to Waiter', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeServiceForRetention();

      final now = DateTime.now().millisecondsSinceEpoch;
      dbService.seedTable(TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        status: 'idle',
        flag: -1,
        createdAt: now,
      ));

      // Manager assigns Table 1 to Waiter W001
      final managerRepo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: '',
      );

      await managerRepo.assignWaiterToTables(
        waiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        tableIds: ['table_1'],
      );

      // Waiter logs in
      final waiterRepo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final waiterStream = waiterRepo.getTablesForWaiterStream('W001');

      final streamExpectation = expectLater(
        waiterStream,
        emits(predicate<List<TableModel>>((tables) {
          return tables.length == 1 &&
              tables.first.id == 'table_1' &&
              tables.first.assignedWaiterId == 'W001' &&
              tables.first.isUnlocked == true;
        })),
      );

      await streamExpectation;
      managerRepo.dispose();
      waiterRepo.dispose();
    });

    test('2. Waiter logs out and logs back in -> Previously assigned device is automatically fetched without manager intervention', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeServiceForRetention();

      final now = DateTime.now().millisecondsSinceEpoch;
      dbService.seedTable(TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        status: 'idle',
        flag: -1,
        isUnlocked: true,
        createdAt: now,
      ));

      // --- Session 1: Waiter is logged in ---
      final waiterRepoSession1 = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      // Waiter logs out (dispose repository session)
      waiterRepoSession1.dispose();

      // --- Session 2: Waiter logs back in directly ---
      final waiterRepoSession2 = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final streamExpectation = expectLater(
        waiterRepoSession2.getTablesForWaiterStream('W001'),
        emits(predicate<List<TableModel>>((tables) {
          return tables.length == 1 &&
              tables.first.id == 'table_2' &&
              tables.first.tableNumber == 2 &&
              tables.first.assignedWaiterId == 'W001';
        })),
      );

      await streamExpectation;
      waiterRepoSession2.dispose();
    });

    test('3. Hardware device event on assigned table triggers alert on logged-in waiter session immediately', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeServiceForRetention();

      final now = DateTime.now().millisecondsSinceEpoch;
      dbService.seedTable(TableModel(
        id: 'table_3',
        tableNumber: 3,
        deviceId: 'device_3',
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        status: 'idle',
        flag: -1,
        isUnlocked: true,
        createdAt: now,
      ));

      // Waiter logs in directly
      final waiterRepo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      // Start listening to waiter stream so local assignments sync to bleService
      final sub = waiterRepo.getTablesForWaiterStream('W001').listen((_) {});

      await Future.delayed(const Duration(milliseconds: 30));

      // Hardware button is pressed on Table 3 -> Gateway reports flag: 0
      bleService.processDevicePayloadForTesting({
        'id': 3,
        'tableNumber': 3,
        'flag': 0,
        'online': true,
        'assigned_waiter_id': 'W001',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // Waiter received immediate audio prompt & notification
      expect(nativeNotifCalls.any((c) => c.method == 'playAudioPrompt'), isTrue);
      expect(nativeNotifCalls.any((c) => c.method == 'showNotification'), isTrue);

      await sub.cancel();
      waiterRepo.dispose();
    });

    test('4. Multiple tables assigned to waiter remain persistent across multi-table updates', () async {
      final bleService = BleService();
      final dbService = MockFirebaseRealtimeServiceForRetention();

      final now = DateTime.now().millisecondsSinceEpoch;
      dbService.seedTable(TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: now,
      ));
      dbService.seedTable(TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        assignedWaiterId: 'W001',
        waiterName: 'Ramesh (W001)',
        isUnlocked: true,
        createdAt: now,
      ));

      final waiterRepo = ServiceRequestRepository(
        bleService,
        dbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final streamExpectation = expectLater(
        waiterRepo.getTablesForWaiterStream('W001'),
        emits(predicate<List<TableModel>>((tables) {
          return tables.length == 2 &&
              tables.any((t) => t.id == 'table_1') &&
              tables.any((t) => t.id == 'table_2');
        })),
      );

      await streamExpectation;
      waiterRepo.dispose();
    });
  });
}
