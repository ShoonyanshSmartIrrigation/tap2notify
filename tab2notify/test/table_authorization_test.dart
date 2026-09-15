import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/ble_service.dart';
import 'package:tab2notify/core/services/firebase_realtime_service.dart';
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
    return _tablesController.stream.map((tables) {
      return tables
          .where((t) =>
              t.isUnlocked &&
              (t.assignedWaiterId == waiterId ||
                  t.waiterName == waiterId ||
                  t.waiterName.contains('($waiterId)') ||
                  t.waiterName.contains(waiterId)))
          .toList();
    });
  }

  @override
  Future<void> unlockTable(
    String tableId, {
    String? managerPhone,
    String? managerUid,
  }) async {
    // Mock implementation
  }

  @override
  Future<void> lockTable(
    String tableId, {
    String? managerPhone,
  }) async {
    // Mock implementation
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Table Authorization & Password Verification Tests', () {
    late BleService bleService;
    late MockFirebaseRealtimeService mockDbService;

    setUp(() {
      bleService = BleService();
      mockDbService = MockFirebaseRealtimeService();
    });

    test('1. TableModel defaults to locked (isUnlocked == false)', () {
      const table = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        createdAt: 1000,
      );

      expect(table.isUnlocked, isFalse);
      expect(table.unlockedAt, isNull);
      expect(table.unlockedBy, isNull);
    });

    test('2. TableModel toMap and fromMap serialization preserves is_unlocked state', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lockedTable = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        isUnlocked: false,
        createdAt: now,
      );

      final lockedMap = lockedTable.toMap();
      expect(lockedMap['is_unlocked'], isFalse);

      final deserializedLocked = TableModel.fromMap(lockedMap, 'table_1');
      expect(deserializedLocked.isUnlocked, isFalse);

      final unlockedTable = TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        isUnlocked: true,
        unlockedAt: now,
        unlockedBy: 'manager_123',
        createdAt: now,
      );

      final unlockedMap = unlockedTable.toMap();
      expect(unlockedMap['is_unlocked'], isTrue);
      expect(unlockedMap['unlocked_at'], equals(now));
      expect(unlockedMap['unlocked_by'], equals('manager_123'));

      final deserializedUnlocked = TableModel.fromMap(unlockedMap, 'table_2');
      expect(deserializedUnlocked.isUnlocked, isTrue);
      expect(deserializedUnlocked.unlockedAt, equals(now));
      expect(deserializedUnlocked.unlockedBy, equals('manager_123'));
    });

    test('3. Password validation: custom device password validator succeeds with correct PIN', () async {
      bleService.devicePasswordValidator = (tableId, password) async {
        return password == 'securePIN9876';
      };

      final success = await bleService.verifyDevicePassword(
        tableId: 'table_1',
        password: 'securePIN9876',
      );

      expect(success, isTrue);
      expect(bleService.isTableUnlocked('table_1'), isTrue);
    });

    test('4. Password validation: without matching password validator or GATT, authorization strictly fails', () async {
      bleService.devicePasswordValidator = (tableId, password) async {
        return password == 'securePIN9876';
      };

      // Fails on invalid password
      final failWrong = await bleService.verifyDevicePassword(
        tableId: 'table_99',
        password: 'wrong_password_9999',
      );
      expect(failWrong, isFalse);

      // Fails on arbitrary / previously default 1234
      final fail1234 = await bleService.verifyDevicePassword(
        tableId: 'table_99',
        password: '1234',
      );
      expect(fail1234, isFalse);
    });

    test('5. Waiter Stream strictly filters out locked tables even if assigned', () async {
      final waiterRepo = ServiceRequestRepository(
        bleService,
        mockDbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final now = DateTime.now().millisecondsSinceEpoch;

      final lockedAssignedTable = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        assignedWaiterId: 'W001',
        waiterName: 'Alex (W001)',
        isUnlocked: false, // LOCKED
        createdAt: now,
      );

      final unlockedAssignedTable = TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        assignedWaiterId: 'W001',
        waiterName: 'Alex (W001)',
        isUnlocked: true, // UNLOCKED
        createdAt: now,
      );

      final waiterStream = waiterRepo.getTablesForWaiterStream('W001');

      final streamExpectation = expectLater(
        waiterStream,
        emits(predicate<List<TableModel>>((tables) {
          // Should only contain Table 2 (unlocked), NOT Table 1 (locked)
          return tables.length == 1 &&
              tables.first.id == 'table_2' &&
              tables.first.isUnlocked == true;
        })),
      );

      mockDbService.emitTables([lockedAssignedTable, unlockedAssignedTable]);
      await streamExpectation;
      waiterRepo.dispose();
    });

    test('6. Unlocking a table dynamically delivers it to the assigned waiter', () async {
      final waiterRepo = ServiceRequestRepository(
        bleService,
        mockDbService,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      final now = DateTime.now().millisecondsSinceEpoch;

      final table1Locked = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        assignedWaiterId: 'W001',
        waiterName: 'Alex (W001)',
        isUnlocked: false,
        createdAt: now,
      );

      final table1Unlocked = table1Locked.copyWith(
        isUnlocked: true,
        unlockedAt: now,
      );

      final waiterStream = waiterRepo.getTablesForWaiterStream('W001');

      final streamExpectation = expectLater(
        waiterStream,
        emitsInOrder([
          // Initial emit when locked: empty list for waiter
          predicate<List<TableModel>>((tables) => tables.isEmpty),
          // After manager unlocks table: delivers Table 1 to waiter
          predicate<List<TableModel>>((tables) =>
              tables.length == 1 && tables.first.id == 'table_1' && tables.first.isUnlocked),
        ]),
      );

      mockDbService.emitTables([table1Locked]);
      await Future.delayed(const Duration(milliseconds: 50));
      mockDbService.emitTables([table1Unlocked]);

      await streamExpectation;
      waiterRepo.dispose();
    });

    test('7. Manager verifyAndUnlockTable correctly updates authorization state', () async {
      bleService.devicePasswordValidator = (tableId, password) async {
        return password == 'managerPass555';
      };

      final managerRepo = ServiceRequestRepository(
        bleService,
        mockDbService,
        managerPhone: '9876543210',
        managerUid: 'mgr_uid_1',
      );

      final success = await managerRepo.verifyAndUnlockTable(
        tableId: 'table_5',
        password: 'managerPass555',
      );

      expect(success, isTrue);
      expect(bleService.isTableUnlocked('table_5'), isTrue);

      // Lock table again
      await managerRepo.lockTable('table_5');
      expect(bleService.isTableUnlocked('table_5'), isFalse);

      managerRepo.dispose();
    });

    test('8. Over-The-Air / Local lockTable updates local and repository authorization state', () async {
      await bleService.unlockTableLocally('table_10');
      expect(bleService.isTableUnlocked('table_10'), isTrue);

      await bleService.lockTableLocally('table_10');
      expect(bleService.isTableUnlocked('table_10'), isFalse);
    });
  });
}
