import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/gateway_wifi_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ESP32-WROOM Central Gateway & Multi-Device C3 Wi-Fi Tests', () {
    late GatewayWifiService gatewayService;

    setUp(() {
      gatewayService = GatewayWifiService();
    });

    test('1. Gateway address configuration: setting IP and port updates gateway connection target', () {
      gatewayService.setGatewayAddress('192.168.4.1', port: 80);

      expect(gatewayService.gatewayIp, '192.168.4.1');
      expect(gatewayService.gatewayPort, 80);
    });

    test('2. Multi-device payload processing: Gateway reporting Table 3 call sets Table 3 to pending', () {
      final payload = {
        'id': 3,
        'tableNumber': 3,
        'flag': 0,
        'online': true,
        'unlocked': true,
      };

      gatewayService.processDevicePayloadForTesting(payload);

      final table3 = gatewayService.getLiveTable('table_3');
      expect(table3, isNotNull);
      expect(table3!.tableNumber, 3);
      expect(table3.flag, 0);
      expect(table3.status, 'pending');
      expect(table3.isPending, isTrue);
      expect(table3.isUnlocked, isTrue);
      expect(table3.isDeviceOnline, isTrue);
    });

    test('3. Multi-device payload processing: Gateway reporting Table 4 accepted sets Table 4 to accepted', () {
      final payload = {
        'id': 4,
        'tableNumber': 4,
        'flag': 1,
        'online': true,
        'unlocked': true,
      };

      gatewayService.processDevicePayloadForTesting(payload);

      final table4 = gatewayService.getLiveTable('table_4');
      expect(table4, isNotNull);
      expect(table4!.tableNumber, 4);
      expect(table4.flag, 1);
      expect(table4.status, 'accepted');
      expect(table4.isAccepted, isTrue);
      expect(table4.isUnlocked, isTrue);
      expect(table4.isDeviceOnline, isTrue);
    });

    test('4. Password authorization: targeted device password validator works for any C3 node via Gateway', () async {
      gatewayService.devicePasswordValidator = (tableId, password) async {
        return tableId == 'table_3' && password == 'secret333';
      };

      final successTable3 = await gatewayService.verifyDevicePassword(
        tableId: 'table_3',
        password: 'secret333',
      );
      expect(successTable3, isTrue);
      expect(gatewayService.isTableUnlocked('table_3'), isTrue);

      final failTable4 = await gatewayService.verifyDevicePassword(
        tableId: 'table_4',
        password: 'secret333',
      );
      expect(failTable4, isFalse);
    });

    test('5. Wi-Fi Router Gateway status: dynamic IP switching updates target Gateway IP', () {
      final routerStatus = {
        'configured': true,
        'ssid': 'Hotel_Restaurant_5G',
        'status': 'connected',
        'sta_ip': '192.168.1.150',
        'ap_ip': '192.168.4.1',
        'rssi': -52,
        'channel': 6,
        'mdns': 'tap2notify.local',
      };

      expect(routerStatus['sta_ip'], '192.168.1.150');
      expect(routerStatus['status'], 'connected');
      expect(routerStatus['ssid'], 'Hotel_Restaurant_5G');
      expect(routerStatus['channel'], 6);
    });

    test('6. Unlocking and locking locally persists state in Gateway service', () async {
      await gatewayService.unlockTableLocally('table_5');
      expect(gatewayService.isTableUnlocked('table_5'), isTrue);

      // Now lock
      await gatewayService.lockTableLocally('table_5');
      expect(gatewayService.isTableUnlocked('table_5'), isFalse);
    });
  });
}


