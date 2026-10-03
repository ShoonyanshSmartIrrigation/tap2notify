import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/gateway_wifi_service.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TableModel State Transition & Flag Authority Tests', () {
    test('1. Pending state (flag == 0) takes absolute authority', () {
      const table = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        flag: 0,
        status: 'pending',
        createdAt: 1000,
      );

      expect(table.isPending, isTrue);
      expect(table.isAccepted, isFalse);
      expect(table.isIdle, isFalse);
    });

    test('2. Accepted state (flag == 1) takes absolute authority', () {
      const table = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        flag: 1,
        status: 'accepted',
        createdAt: 1000,
      );

      expect(table.isPending, isFalse);
      expect(table.isAccepted, isTrue);
      expect(table.isIdle, isFalse);
    });

    test('3. Idle state (flag == -1) takes absolute authority over legacy status string', () {
      const table = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        flag: -1,
        status: 'pending', // Simulated stale status from old DB document
        createdAt: 1000,
      );

      // Flag == -1 must guarantee the table is NOT pending and IS idle
      expect(table.isPending, isFalse);
      expect(table.isAccepted, isFalse);
      expect(table.isIdle, isTrue);
    });

    test('4. Hardware Locked state (flag == -2) is considered idle in hospitality status', () {
      const table = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        flag: -2,
        status: 'idle',
        isUnlocked: false,
        createdAt: 1000,
      );

      expect(table.isPending, isFalse);
      expect(table.isAccepted, isFalse);
      expect(table.isIdle, isTrue);
    });

    test('5. TableModel.fromMap normalizes flag and status correctly', () {
      final mapPending = {
        'id': 'table_5',
        'table_number': 5,
        'flag': 0,
        'status': 'idle', // Stale status should be overwritten by flag: 0
        'device_online': true,
      };
      final tablePending = TableModel.fromMap(mapPending, 'table_5');
      expect(tablePending.flag, equals(0));
      expect(tablePending.status, equals('pending'));
      expect(tablePending.isPending, isTrue);
      expect(tablePending.isAccepted, isFalse);
      expect(tablePending.isIdle, isFalse);

      final mapAccepted = {
        'id': 'table_5',
        'table_number': 5,
        'flag': 1,
        'status': 'pending', // Stale status should be overwritten by flag: 1
        'device_online': true,
      };
      final tableAccepted = TableModel.fromMap(mapAccepted, 'table_5');
      expect(tableAccepted.flag, equals(1));
      expect(tableAccepted.status, equals('accepted'));
      expect(tableAccepted.isPending, isFalse);
      expect(tableAccepted.isAccepted, isTrue);
      expect(tableAccepted.isIdle, isFalse);

      final mapIdle = {
        'id': 'table_5',
        'table_number': 5,
        'flag': -1,
        'status': 'accepted', // Stale status should be overwritten by flag: -1
        'device_online': true,
      };
      final tableIdle = TableModel.fromMap(mapIdle, 'table_5');
      expect(tableIdle.flag, equals(-1));
      expect(tableIdle.status, equals('idle'));
      expect(tableIdle.isPending, isFalse);
      expect(tableIdle.isAccepted, isFalse);
      expect(tableIdle.isIdle, isTrue);
    });
    test('6. TableModel.copyWith auto-synchronizes flag and status', () {
      const tableIdle = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        flag: -1,
        status: 'idle',
        createdAt: 1000,
      );

      // Transition to Pending via copyWith(flag: 0)
      final tablePending = tableIdle.copyWith(flag: 0);
      expect(tablePending.flag, equals(0));
      expect(tablePending.status, equals('pending'));
      expect(tablePending.isPending, isTrue);
      expect(tablePending.isIdle, isFalse);

      // Transition to Accepted via copyWith(flag: 1)
      final tableAccepted = tablePending.copyWith(flag: 1);
      expect(tableAccepted.flag, equals(1));
      expect(tableAccepted.status, equals('accepted'));
      expect(tableAccepted.isAccepted, isTrue);
      expect(tableAccepted.isPending, isFalse);

      // Transition back to Idle via copyWith(flag: -1)
      final tableReset = tableAccepted.copyWith(flag: -1);
      expect(tableReset.flag, equals(-1));
      expect(tableReset.status, equals('idle'));
      expect(tableReset.isIdle, isTrue);
      expect(tableReset.isAccepted, isFalse);
    });
  });

  group('GatewayWifiService State Transitions & Table Resolution', () {
    late GatewayWifiService wifiService;

    setUp(() {
      wifiService = GatewayWifiService();
      wifiService.resetForTesting();
    });

    tearDown(() {
      wifiService.resetForTesting();
    });

    test('1. Full Lifecycle: Idle -> Pending (Touch 1) -> Accepted (Touch 2) -> Idle (Touch 3/Timeout)', () {
      // Step 1: Initial discovery (IDLE)
      wifiService.processDevicePayloadForTesting({
        'id': '1',
        'tableNumber': 1,
        'flag': -1,
        'online': true,
        'unlocked': true,
      });

      var table = wifiService.getLiveTable('table_1');
      expect(table, isNotNull);
      expect(table!.isIdle, isTrue);
      expect(table.isPending, isFalse);
      expect(table.isAccepted, isFalse);

      // Step 2: Customer presses touch button -> Flag 0 (PENDING)
      wifiService.processDevicePayloadForTesting({
        'id': '1',
        'tableNumber': 1,
        'flag': 0,
        'online': true,
        'unlocked': true,
      });

      table = wifiService.getLiveTable('table_1');
      expect(table!.isPending, isTrue);
      expect(table.isAccepted, isFalse);
      expect(table.isIdle, isFalse);
      expect(table.requestSentAt, isNotNull);

      // Step 3: Waiter or Device accepts request -> Flag 1 (ACCEPTED)
      wifiService.processDevicePayloadForTesting({
        'id': '1',
        'tableNumber': 1,
        'flag': 1,
        'online': true,
        'unlocked': true,
      });

      table = wifiService.getLiveTable('table_1');
      expect(table!.isPending, isFalse);
      expect(table.isAccepted, isTrue);
      expect(table.isIdle, isFalse);

      // Step 4: Reset back to IDLE
      wifiService.processDevicePayloadForTesting({
        'id': '1',
        'tableNumber': 1,
        'flag': -1,
        'online': true,
        'unlocked': true,
      });

      table = wifiService.getLiveTable('table_1');
      expect(table!.isPending, isFalse);
      expect(table.isAccepted, isFalse);
      expect(table.isIdle, isTrue);
    });

    test('2. Flexible table identifier lookup (1, table_1, device_1)', () {
      wifiService.processDevicePayloadForTesting({
        'id': '7',
        'tableNumber': 7,
        'flag': 0,
        'online': true,
        'unlocked': true,
      });

      expect(wifiService.getLiveTable('7'), isNotNull);
      expect(wifiService.getLiveTable('table_7'), isNotNull);
      expect(wifiService.getLiveTable('device_7'), isNotNull);
      expect(wifiService.isTableOnline('7'), isTrue);
      expect(wifiService.isTableOnline('table_7'), isTrue);
    });

    test('3. Local state actions (acceptTableRequest & resetTableStatus)', () async {
      wifiService.processDevicePayloadForTesting({
        'id': '3',
        'tableNumber': 3,
        'flag': 0,
        'online': true,
        'unlocked': true,
      });

      // Accept locally
      await wifiService.acceptTableRequest(
        tableId: 'table_3',
        waiterName: 'John',
      );

      var table = wifiService.getLiveTable('table_3');
      expect(table!.isAccepted, isTrue);
      expect(table.isPending, isFalse);
      expect(table.waiterName, equals('John'));

      // Reset locally
      await wifiService.resetTableStatus('table_3');
      table = wifiService.getLiveTable('table_3');
      expect(table!.isIdle, isTrue);
      expect(table.isAccepted, isFalse);
      expect(table.isPending, isFalse);
    });

    test('4. String flag and status-only payloads parse correctly', () {
      // String flag "0" -> Pending
      wifiService.processDevicePayloadForTesting({
        'id': '4',
        'tableNumber': 4,
        'flag': '0',
        'online': true,
      });
      var table = wifiService.getLiveTable('table_4');
      expect(table!.isPending, isTrue);
      expect(table.flag, equals(0));

      // String flag "1" -> Accepted
      wifiService.processDevicePayloadForTesting({
        'id': '4',
        'tableNumber': 4,
        'flag': '1',
        'online': true,
      });
      table = wifiService.getLiveTable('table_4');
      expect(table!.isAccepted, isTrue);
      expect(table.flag, equals(1));

      // Status payload without flag field -> Status 'pending'
      wifiService.processDevicePayloadForTesting({
        'id': '5',
        'tableNumber': 5,
        'status': 'pending',
        'online': true,
      });
      table = wifiService.getLiveTable('table_5');
      expect(table!.isPending, isTrue);
      expect(table.flag, equals(0));
    });

    test('5. syncTableFromCloud updates local gateway cache', () {
      final cloudTable = TableModel(
        id: 'table_8',
        tableNumber: 8,
        deviceId: 'device_8',
        flag: 1,
        status: 'accepted',
        waiterName: 'Sarah',
        createdAt: 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      wifiService.syncTableFromCloud(cloudTable);
      final cached = wifiService.getLiveTable('table_8');
      expect(cached, isNotNull);
      expect(cached!.isAccepted, isTrue);
      expect(cached.waiterName, equals('Sarah'));
    });
  });
}
