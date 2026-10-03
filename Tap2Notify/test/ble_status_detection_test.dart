import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/gateway_wifi_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wi-Fi Gateway Device Status Detection Tests', () {
    late GatewayWifiService gatewayService;

    setUp(() {
      gatewayService = GatewayWifiService();
    });

    test('Primary device payload with REQ (flag: 0) sets Table 2 to pending', () {
      final payload = {
        'id': 2,
        'tableNumber': 2,
        'flag': 0,
        'online': true,
        'unlocked': true,
      };

      gatewayService.processDevicePayloadForTesting(payload);

      final table = gatewayService.getLiveTable('table_2');
      expect(table, isNotNull);
      expect(table!.tableNumber, 2);
      expect(table.flag, 0);
      expect(table.status, 'pending');
      expect(table.isPending, isTrue);
      expect(table.isAccepted, isFalse);
    });

    test('Primary device payload with IDLE (flag: -1) sets Table 2 to idle', () {
      final payload = {
        'id': 2,
        'tableNumber': 2,
        'flag': -1,
        'online': true,
        'unlocked': true,
      };

      gatewayService.processDevicePayloadForTesting(payload);

      final table = gatewayService.getLiveTable('table_2');
      expect(table, isNotNull);
      expect(table!.flag, -1);
      expect(table.status, 'idle');
      expect(table.isIdle, isTrue);
      expect(table.isAccepted, isFalse);
    });

    test('Locked device payload (flag: -2 / unlocked: false) keeps table idle and locked', () {
      final payload = {
        'id': 2,
        'tableNumber': 2,
        'flag': -2,
        'online': true,
        'unlocked': false,
      };

      gatewayService.processDevicePayloadForTesting(payload);

      final table = gatewayService.getLiveTable('table_2');
      expect(table, isNotNull);
      expect(table!.flag, -1);
      expect(table.status, 'idle');
      expect(table.isUnlocked, isFalse);
    });

    test('Resetting Table 2 via resetTableStatus sets status to idle', () async {
      await gatewayService.resetTableStatus('table_2');
      expect(gatewayService.getLiveTable('table_2')?.flag, -1);
      expect(gatewayService.getLiveTable('table_2')?.status, 'idle');
    });

    test('resetAllTables resets all tracked tables to idle (flag: -1)', () async {
      // First, set table 2 to accepted
      await gatewayService.acceptTableRequest(tableId: 'table_2', waiterName: 'Rahul');
      expect(gatewayService.getLiveTable('table_2')?.isAccepted, isTrue);

      // Now reset all
      await gatewayService.resetAllTables();
      expect(gatewayService.getLiveTable('table_2')?.flag, -1);
      expect(gatewayService.getLiveTable('table_2')?.status, 'idle');
      expect(gatewayService.getLiveTable('table_2')?.waiterName, '');
    });

    test('Flexible device table identification (table_3, 3) parses correctly', () {
      final payload = {
        'id': 'table_3',
        'flag': 0,
        'online': true,
        'unlocked': true,
      };

      gatewayService.processDevicePayloadForTesting(payload);

      final table = gatewayService.getLiveTable('table_3');
      expect(table, isNotNull);
      expect(table!.tableNumber, 3);
      expect(table.flag, 0);
      expect(table.status, 'pending');
      expect(table.isPending, isTrue);
    });

    test('Flexible lookup by numeric string "3" finds "table_3" and online status', () {
      final payload = {
        'id': 'table_3',
        'flag': 0,
        'online': true,
        'unlocked': true,
      };

      gatewayService.processDevicePayloadForTesting(payload);

      expect(gatewayService.getLiveTable('3')?.tableNumber, 3);
      expect(gatewayService.isTableOnline('3'), isTrue);
      expect(gatewayService.isTableOnline('table_3'), isTrue);
    });
  });
}


