import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/ble_service.dart';
import 'package:tab2notify/core/services/device_credential_service.dart';
import 'package:tab2notify/core/services/firebase_realtime_service.dart';
import 'package:tab2notify/features/service_requests/data/service_request_repository.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';

class MockRealtimeDbForAuth extends FirebaseRealtimeService {
  final Map<String, Map<String, dynamic>> _mockCloudTables = {};
  final StreamController<List<TableModel>> _tablesController =
      StreamController<List<TableModel>>.broadcast();

  void registerCloudTable(String tableId, Map<String, dynamic> data) {
    _mockCloudTables[tableId] = Map<String, dynamic>.from(data);
  }

  @override
  Future<Map<String, dynamic>?> fetchRegisteredTable(
    String identifier, {
    String? managerPhone,
    String? managerUid,
  }) async {
    final clean = identifier.trim();
    if (_mockCloudTables.containsKey(clean)) return _mockCloudTables[clean];
    if (_mockCloudTables.containsKey('table_$clean')) return _mockCloudTables['table_$clean'];
    for (final entry in _mockCloudTables.entries) {
      if (entry.value['device_id'] == clean ||
          entry.value['table_number'].toString() == clean) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Future<void> unlockTable(
    String tableId, {
    String? managerPhone,
    String? managerUid,
    String? password,
  }) async {
    final target = _mockCloudTables[tableId];
    if (target != null) {
      target['is_unlocked'] = true;
      if (password != null) target['device_password'] = password;
    }
  }

  @override
  Future<void> lockTable(
    String tableId, {
    String? managerPhone,
    String? managerUid,
  }) async {
    final target = _mockCloudTables[tableId];
    if (target != null) {
      target['is_unlocked'] = false;
    }
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

  group('Dynamic Device Authentication Flow Tests', () {
    late BleService bleService;
    late MockRealtimeDbForAuth mockDb;
    late DeviceCredentialService credentialService;
    late ServiceRequestRepository repository;

    setUp(() {
      bleService = BleService();
      bleService.resetForTesting();
      mockDb = MockRealtimeDbForAuth();
      credentialService = DeviceCredentialService();

      repository = ServiceRequestRepository(
        bleService,
        mockDb,
        credentialService: credentialService,
        managerPhone: '9876543210',
        managerUid: 'manager_uid_1',
      );
    });

    tearDown(() {
      repository.dispose();
    });

    test('1. Unregistered Device ID is rejected with descriptive error message', () async {
      expect(
        () => repository.verifyDeviceOwnership(
          deviceId: 'table_999',
          password: 'some_password',
        ),
        throwsA(predicate<Exception>((e) =>
            e.toString().contains('not registered in the system'))),
      );
      expect(bleService.isTableUnlocked('table_999'), isFalse);
    });

    test('2. Registered table with incorrect password fails and is strictly rejected', () async {
      mockDb.registerCloudTable('table_5', {
        'id': 'table_5',
        'table_number': 5,
        'device_id': 'device_5',
        'device_password': 'securePin555',
        'is_unlocked': false,
      });

      expect(
        () => repository.verifyDeviceOwnership(
          deviceId: '5',
          password: 'wrong_password',
        ),
        throwsA(predicate<Exception>((e) =>
            e.toString().contains('Incorrect password'))),
      );
      expect(bleService.isTableUnlocked('table_5'), isFalse);
    });

    test('3. Registered table with correct password authenticates, unlocks and admits device', () async {
      mockDb.registerCloudTable('table_2', {
        'id': 'table_2',
        'table_number': 2,
        'device_id': 'Shoon2',
        'device_password': 'myDynamicPassword123',
        'is_unlocked': false,
      });

      bleService.devicePasswordValidator = (tableId, pwd) async =>
          pwd == 'myDynamicPassword123';

      final success = await repository.verifyDeviceOwnership(
        deviceId: 'Shoon2',
        password: 'myDynamicPassword123',
      );

      expect(success, isTrue);
      expect(bleService.isTableUnlocked('table_2'), isTrue);
      expect(bleService.isDeviceOwnershipVerified('Shoon2'), isTrue);

      // Verify dynamic credential was saved locally
      final savedPass = credentialService.getCredential('Shoon2', managerPhone: '9876543210');
      expect(savedPass, equals('myDynamicPassword123'));
    });

    test('4. Dynamically authenticated device is restored across repository instantiations', () async {
      // Save dynamic credential
      await credentialService.saveCredential(
        '10',
        'dynamicPass10',
        managerPhone: '9876543210',
      );

      // Create brand new fresh BleService and fresh Repository
      final freshBle = BleService();
      freshBle.resetForTesting();
      final freshRepo = ServiceRequestRepository(
        freshBle,
        mockDb,
        credentialService: credentialService,
        managerPhone: '9876543210',
      );

      // Device 10 should have its credential pre-populated dynamically without hardcoded files
      expect(freshBle.getStoredPassword('10'), equals('dynamicPass10'));

      freshRepo.dispose();
    });

    test('5. Lock table removes dynamic credential and relocks device', () async {
      mockDb.registerCloudTable('table_3', {
        'id': 'table_3',
        'table_number': 3,
        'device_id': 'device_3',
        'device_password': 'pin3',
        'is_unlocked': true,
      });

      bleService.devicePasswordValidator = (tableId, pwd) async => pwd == 'pin3';

      await repository.verifyDeviceOwnership(
        deviceId: '3',
        password: 'pin3',
      );
      expect(bleService.isTableUnlocked('table_3'), isTrue);

      // Manager locks the table
      await repository.lockTable('table_3');
      expect(bleService.isTableUnlocked('table_3'), isFalse);
      expect(credentialService.getCredential('3', managerPhone: '9876543210'), isNull);
    });
  });
}
