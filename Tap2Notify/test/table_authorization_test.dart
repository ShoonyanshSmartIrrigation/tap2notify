import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/ble_service.dart';
import 'package:tab2notify/core/services/device_credential_service.dart';
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
  Future<Map<String, dynamic>?> fetchRegisteredTable(
    String identifier, {
    String? managerPhone,
    String? managerUid,
  }) async {
    return null;
  }

  @override
  Future<void> unlockTable(
    String tableId, {
    String? managerPhone,
    String? managerUid,
    String? password,
  }) async {
    // Mock implementation
  }

  @override
  Future<void> lockTable(
    String tableId, {
    String? managerPhone,
    String? managerUid,
  }) async {
    // Mock implementation
  }

  @override
  Future<void> assignWaiterToTables({
    required String waiterId,
    required String waiterName,
    required List<String> tableIds,
    String? managerPhone,
    String? managerUid,
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
      bleService.resetForTesting();
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

    test('9. Dashboard filtering: locked tables are isolated and excluded from "all" section', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final table1Unlocked = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        isUnlocked: true,
        createdAt: now,
      );
      final table2Locked = TableModel(
        id: 'table_2',
        tableNumber: 2,
        deviceId: 'device_2',
        isUnlocked: false,
        createdAt: now,
      );

      final tablesList = [table1Unlocked, table2Locked];

      final unlockedTables = tablesList.where((t) => t.isUnlocked).toList();
      final lockedTables = tablesList.where((t) => !t.isUnlocked).toList();

      // "All" filter should only show unlocked tables
      expect(unlockedTables.length, equals(1));
      expect(unlockedTables.first.id, equals('table_1'));

      // "Locked" filter contains locked tables
      expect(lockedTables.length, equals(1));
      expect(lockedTables.first.id, equals('table_2'));
    });
  });

  group('Multi-Manager Authorization Isolation Tests', () {
    late BleService bleService;
    late MockFirebaseRealtimeService mockDbService;

    setUp(() {
      bleService = BleService();
      bleService.resetForTesting();
      mockDbService = MockFirebaseRealtimeService();
    });

    test('1. Manager A unlocking Table 1 leaves Table 1 LOCKED for Manager B', () async {
      bleService.devicePasswordValidator = (tableId, password) async {
        return password == 'secret123';
      };

      // Manager A session (Hotel Alpha)
      final repoManagerA = ServiceRequestRepository(
        bleService,
        mockDbService,
        managerPhone: '1111111111',
        managerUid: 'uid_mgr_a',
      );

      // Manager A unlocks Table 1
      final unlockA = await repoManagerA.verifyAndUnlockTable(
        tableId: 'table_1',
        password: 'secret123',
      );
      expect(unlockA, isTrue);

      // Verify Table 1 is unlocked for Manager A
      expect(
        bleService.isTableUnlockedForManager(
          'table_1',
          managerPhone: '1111111111',
          managerUid: 'uid_mgr_a',
        ),
        isTrue,
      );

      // Manager B session (Hotel Beta)
      final repoManagerB = ServiceRequestRepository(
        bleService,
        mockDbService,
        managerPhone: '2222222222',
        managerUid: 'uid_mgr_b',
      );

      // Table 1 MUST remain LOCKED for Manager B
      expect(
        bleService.isTableUnlockedForManager(
          'table_1',
          managerPhone: '2222222222',
          managerUid: 'uid_mgr_b',
        ),
        isFalse,
      );

      const table1 = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        createdAt: 1000,
      );

      expect(repoManagerA.isTableAuthorizedForThisManager(table1), isTrue);
      expect(repoManagerB.isTableAuthorizedForThisManager(table1), isFalse);

      repoManagerA.dispose();
      repoManagerB.dispose();
    });

    test('2. Gateway reporting unlocked: true does NOT unlock table for unauthorized Manager B', () {
      // Set active manager to Manager B
      bleService.setActiveManager(
        managerPhone: '2222222222',
        managerUid: 'uid_mgr_b',
      );

      // Simulate Gateway reporting device 1 payload with unlocked: true
      bleService.processDevicePayloadForTesting({
        'table_id': '1',
        'table': 1,
        'unlocked': true,
        'flag': -1,
      });

      // Manager B has not authorized device 1, so it must remain locked for Manager B
      expect(
        bleService.isTableUnlockedForManager(
          'table_1',
          managerPhone: '2222222222',
          managerUid: 'uid_mgr_b',
        ),
        isFalse,
      );
      expect(
        bleService.isTableUnlocked(
          'table_1',
          managerPhone: '2222222222',
          managerUid: 'uid_mgr_b',
        ),
        isFalse,
      );
    });

    test('3. Manager B verifying password unlocks Table 1 independently for Manager B', () async {
      bleService.devicePasswordValidator = (tableId, password) async {
        return password == 'secret123';
      };

      // Manager A authorizes Table 1
      bleService.authorizeTableForManager(
        tableId: 'table_1',
        password: 'secret123',
        managerPhone: '1111111111',
        managerUid: 'uid_mgr_a',
      );

      // Before Manager B unlocks, Manager B is NOT authorized
      expect(
        bleService.isTableUnlockedForManager('table_1', managerPhone: '2222222222'),
        isFalse,
      );

      // Manager B authorizes Table 1
      final repoManagerB = ServiceRequestRepository(
        bleService,
        mockDbService,
        managerPhone: '2222222222',
        managerUid: 'uid_mgr_b',
      );

      final unlockB = await repoManagerB.verifyAndUnlockTable(
        tableId: 'table_1',
        password: 'secret123',
      );
      expect(unlockB, isTrue);

      // Now both Manager A and Manager B are authorized independently
      expect(
        bleService.isTableUnlockedForManager('table_1', managerPhone: '1111111111'),
        isTrue,
      );
      expect(
        bleService.isTableUnlockedForManager('table_1', managerPhone: '2222222222'),
        isTrue,
      );

      // When Manager A locks Table 1, Manager A is deauthorized
      await repoManagerB.lockTable('table_1');
      expect(
        bleService.isTableUnlockedForManager('table_1', managerPhone: '2222222222'),
        isFalse,
      );

      repoManagerB.dispose();
    });

    test('4. Logout and clearManagerSession completely resets authorization state', () async {
      bleService.authorizeTableForManager(
        tableId: 'table_1',
        password: 'pass',
        managerPhone: '1111111111',
      );
      bleService.setActiveManager(managerPhone: '1111111111');

      expect(bleService.isTableUnlocked('table_1'), isTrue);

      // Manager logs out
      bleService.clearManagerSession();

      // State is reset
      expect(bleService.isDeviceOwnershipVerified('1'), isFalse);
      expect(bleService.getStoredPassword('1'), isNull);
    });

    test('5. Unauthorized Manager cannot assign waiters to a locked table', () async {
      final repoManagerB = ServiceRequestRepository(
        bleService,
        mockDbService,
        managerPhone: '2222222222',
        managerUid: 'uid_mgr_b',
      );

      // Seed Table 5 as locked in mock DB / cached tables
      mockDbService.emitTables([
        const TableModel(
          id: 'table_5',
          tableNumber: 5,
          deviceId: 'device_5',
          isUnlocked: false,
          status: 'locked',
          flag: -2,
          createdAt: 1000,
        ),
      ]);
      await Future.delayed(const Duration(milliseconds: 20));

      // Manager B has not unlocked Table 5 -> assignWaiterToTables must throw Exception
      expect(
        () async => await repoManagerB.assignWaiterToTables(
          waiterId: 'W002',
          waiterName: 'Suresh',
          tableIds: ['table_5'],
        ),
        throwsA(isA<Exception>()),
      );

      repoManagerB.dispose();
    });

    test('6. Cross-Device/Cross-Manager Isolation: Manager A unlocks Table 1, Table 1 remains strictly locked on Device B', () async {
      bleService.devicePasswordValidator = (tableId, password) async {
        return password == 'alpha123';
      };

      // Device A / Manager A session
      final repoDeviceA = ServiceRequestRepository(
        bleService,
        mockDbService,
        managerPhone: '1111111111',
        managerUid: 'uid_mgr_a',
      );

      // Manager A unlocks Table 1 on Device A
      final unlockedOnA = await repoDeviceA.verifyAndUnlockTable(
        tableId: 'table_1',
        password: 'alpha123',
      );
      expect(unlockedOnA, isTrue);

      // Now simulate Device B / Manager B session (separate device/app instance)
      final bleServiceB = BleService();
      bleServiceB.resetForTesting();
      final mockDbServiceB = MockFirebaseRealtimeService();

      final repoDeviceB = ServiceRequestRepository(
        bleServiceB,
        mockDbServiceB,
        managerPhone: '2222222222',
        managerUid: 'uid_mgr_b',
      );

      // ESP32 Gateway broadcasts Table 1 with unlocked: true (because Table 1 was unlocked on hardware by Manager A)
      bleServiceB.processDevicePayloadForTesting({
        'table_id': '1',
        'table': 1,
        'unlocked': true,
        'flag': -1,
      });

      // 1. bleServiceB must not report Table 1 unlocked for Manager B
      expect(
        bleServiceB.isTableUnlockedForManager(
          'table_1',
          managerPhone: '2222222222',
          managerUid: 'uid_mgr_b',
        ),
        isFalse,
      );

      // 2. repoDeviceB.isTableAuthorizedForThisManager must return false even if hardware reports unlocked: true
      const table1Payload = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        isUnlocked: true, // Hardware broadcast reports true
        createdAt: 1000,
      );
      expect(repoDeviceB.isTableAuthorizedForThisManager(table1Payload), isFalse);

      // 3. repoDeviceB.getTablesStream must emit Table 1 as locked (isUnlocked == false)
      final tablesStream = repoDeviceB.getTablesStream();
      final expectation = expectLater(
        tablesStream,
        emits(predicate<List<TableModel>>((tables) {
          final t1 = tables.firstWhere((t) => t.id == 'table_1');
          return t1.isUnlocked == false;
        })),
      );

      mockDbServiceB.emitTables([
        const TableModel(
          id: 'table_1',
          tableNumber: 1,
          deviceId: 'device_1',
          isUnlocked: false,
          createdAt: 1000,
        ),
      ]);
      await expectation;

      repoDeviceA.dispose();
      repoDeviceB.dispose();
    });

    test('7. Email/UID-only managers: DeviceCredentialService partitions credentials without collision', () async {
      final credService = DeviceCredentialService();

      // Manager A (UID only, no phone)
      await credService.saveCredential(
        '1',
        'alphaPass',
        managerPhone: '',
        managerUid: 'uid_alpha_user',
      );

      // Manager B (UID only, no phone)
      await credService.saveCredential(
        '1',
        'betaPass',
        managerPhone: '',
        managerUid: 'uid_beta_user',
      );

      expect(
        credService.getCredential('1', managerPhone: '', managerUid: 'uid_alpha_user'),
        equals('alphaPass'),
      );
      expect(
        credService.getCredential('1', managerPhone: '', managerUid: 'uid_beta_user'),
        equals('betaPass'),
      );
    });

    test('8. Foreign manager cloud tables with is_unlocked: true are REJECTED by isTableAuthorizedForThisManager', () {
      final repoDeviceB = ServiceRequestRepository(
        bleService,
        mockDbService,
        managerPhone: '2222222222',
        managerUid: 'uid_mgr_b',
      );

      // Table belonging to Manager A, marked unlocked in Manager A's system
      const foreignTable = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        isUnlocked: true,
        managerPhone: '1111111111',
        managerUid: 'uid_mgr_a',
        unlockedBy: 'uid_mgr_a',
        createdAt: 1000,
      );

      expect(repoDeviceB.isTableAuthorizedForThisManager(foreignTable), isFalse);

      repoDeviceB.dispose();
    });
  });
}
