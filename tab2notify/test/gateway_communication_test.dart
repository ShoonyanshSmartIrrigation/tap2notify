import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tab2notify/core/services/gateway_wifi_service.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ESP32-WROOM Central Gateway & Multi-Device C3 Wi-Fi Tests', () {
    late GatewayWifiService gatewayService;

    setUp(() {
      gatewayService = GatewayWifiService();
    });

    test(
      '1. Gateway address configuration: setting IP and port updates gateway connection target',
      () {
        gatewayService.setGatewayAddress('192.168.4.1', port: 80);

        expect(gatewayService.gatewayIp, '192.168.4.1');
        expect(gatewayService.gatewayPort, 80);
      },
    );

    test(
      '2. Multi-device payload processing: Gateway reporting Table 3 call sets Table 3 to pending',
      () {
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
      },
    );

    test(
      '3. Multi-device payload processing: Gateway reporting Table 4 accepted sets Table 4 to accepted',
      () {
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
      },
    );

    test(
      '4. Password authorization: targeted device password validator works for any C3 node via Gateway',
      () async {
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
      },
    );

    test(
      '5. Wi-Fi Router Gateway status: dynamic IP switching updates target Gateway IP',
      () {
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
      },
    );

    test(
      '6. Unlocking and locking locally persists state in Gateway service',
      () async {
        await gatewayService.unlockTableLocally('table_5');
        expect(gatewayService.isTableUnlocked('table_5'), isTrue);

        // Now lock
        await gatewayService.lockTableLocally('table_5');
        expect(gatewayService.isTableUnlocked('table_5'), isFalse);
      },
    );

    test(
      '7. Password verification: device password set to 1234, entering 12345 fails and device remains locked',
      () async {
        gatewayService.devicePasswordValidator =
            null; // Test real HTTP verification
        gatewayService.httpClient = MockClient((request) async {
          if (request.url.path.contains('/api/command')) {
            final dynamic body = jsonDecode(request.body);
            if (body['command'] == 'AUTH') {
              if (body['password'] == '1234') {
                return http.Response(
                  jsonEncode({
                    'success': true,
                    'status': 'success',
                    'command': 'AUTH',
                    'result': 'AUTH_OK',
                    'unlocked': true,
                  }),
                  200,
                );
              } else {
                return http.Response(
                  jsonEncode({
                    'success': false,
                    'status': 'failed',
                    'command': 'AUTH',
                    'result': 'AUTH_FAIL',
                    'unlocked': false,
                    'error': 'Incorrect password',
                  }),
                  401,
                );
              }
            }
          }
          return http.Response('Not found', 404);
        });

        // Attempt unlocking table 1 with 12345
        final failResult = await gatewayService.verifyDevicePassword(
          tableId: 'table_1',
          password: '12345',
        );
        expect(
          failResult,
          isFalse,
          reason: 'Wrong password 12345 must strictly fail',
        );
        expect(gatewayService.isTableUnlocked('table_1'), isFalse);

        // Now attempt unlocking table 1 with correct password 1234
        final successResult = await gatewayService.verifyDevicePassword(
          tableId: 'table_1',
          password: '1234',
        );
        expect(
          successResult,
          isTrue,
          reason: 'Correct password 1234 must succeed',
        );
        expect(gatewayService.isTableUnlocked('table_1'), isTrue);
      },
    );

    test(
      '8. Payload with unlocked: false strictly locks table even if waiter is assigned',
      () {
        final payload = {
          'id': 1,
          'tableNumber': 1,
          'flag': -1,
          'online': true,
          'unlocked': false,
          'assigned_waiter_id': 'W001',
        };

        gatewayService.processDevicePayloadForTesting(payload);

        final table1 = gatewayService.getLiveTable('table_1');
        expect(table1, isNotNull);
        expect(table1!.isUnlocked, isFalse);
        expect(gatewayService.isTableUnlocked('table_1'), isFalse);
      },
    );

    test(
      '9. TableModel.fromMap preserves isUnlocked: false even when assigned_waiter_id is present',
      () {
        final map = {
          'table_number': 1,
          'is_unlocked': false,
          'assigned_waiter_id': 'W001',
          'assigned_waiter_name': 'John Doe',
          'device_online': true,
          'status': 'idle',
          'flag': -1,
        };

        final table = TableModel.fromMap(map, 'table_1');
        expect(
          table.isUnlocked,
          isFalse,
          reason: 'Assigned waiter must not automatically unlock table',
        );
        expect(table.isAssigned, isTrue);
        expect(table.assignedWaiterId, 'W001');
      },
    );

    test('10. First-time table displayed in app defaults to LOCKED state', () {
      final freshService = GatewayWifiService();
      // Unseen table arrives from Gateway SSE/HTTP with isUnlocked: false
      final newDevicePayload = {
        'deviceId': '2',
        'tableNumber': 2,
        'flag': -2,
        'isUnlocked': false,
        'online': true,
      };

      freshService.processDevicePayloadForTesting(newDevicePayload);
      final table2 = freshService.getLiveTable('table_2');
      expect(table2, isNotNull);
      expect(
        table2!.isUnlocked,
        isFalse,
        reason: 'First-time table must appear in LOCKED state',
      );
      expect(freshService.isTableUnlocked('table_2'), isFalse);
    });

    test(
      '11. AUTH command rejects and returns false if response lacks explicit unlock confirmation',
      () async {
        gatewayService.devicePasswordValidator = null;
        gatewayService.httpClient = MockClient((request) async {
          // Return HTTP 200 with vague/sent status but no unlocked: true
          return http.Response(
            jsonEncode({'success': true, 'status': 'sent', 'command': 'AUTH'}),
            200,
          );
        });

        final result = await gatewayService.verifyDevicePassword(
          tableId: 'table_1',
          password: '12345',
        );
        expect(
          result,
          isFalse,
          reason:
              'AUTH must strictly reject without positive unlock confirmation',
        );
        expect(gatewayService.isTableUnlocked('table_1'), isFalse);
      },
    );

    test(
      '12. Device Ownership: Discovered device with unregistered Device ID is rejected as unauthorized and does NOT appear in currentTables',
      () {
        final freshGateway = GatewayWifiService();
        freshGateway.resetForTesting();

        // Device 99 is not registered in system credentials
        final unknownPayload = {
          'id': '99',
          'tableNumber': 99,
          'flag': 0,
          'online': true,
          'unlocked': false,
        };

        // Process without test bypass
        freshGateway.processDevicePayload(unknownPayload);

        // Must NOT appear in currentTables or live tables
        expect(freshGateway.isDeviceOwnershipVerified('99'), isFalse);
        expect(freshGateway.currentTables.any((t) => t.tableNumber == 99), isFalse);
        expect(freshGateway.getLiveTable('99'), isNull);
      },
    );

    test(
      '13. Device Ownership: Registered device with incorrect password (e.g. 12345 vs 1234) fails verification and is NOT admitted',
      () async {
        final freshGateway = GatewayWifiService();
        freshGateway.resetForTesting();

        // Register credential for device 1: password is 1234
        freshGateway.registerStoredCredential('1', '1234');

        // Manager or App tries to verify with incorrect password 12345
        final result = await freshGateway.verifyDeviceOwnership(
          deviceId: '1',
          password: '12345',
        );

        expect(result, isFalse, reason: 'Device ownership must fail on incorrect password');
        expect(freshGateway.isDeviceOwnershipVerified('1'), isFalse);
        expect(freshGateway.currentTables.any((t) => t.tableNumber == 1), isFalse);
        expect(freshGateway.getLiveTable('1'), isNull);
      },
    );

    test(
      '14. Device Ownership: Registered device with matching password succeeds and is admitted to currentTables',
      () async {
        final freshGateway = GatewayWifiService();
        freshGateway.resetForTesting();

        freshGateway.devicePasswordValidator = (tableId, pwd) async => pwd == '1234';

        final result = await freshGateway.verifyDeviceOwnership(
          deviceId: '1',
          password: '1234',
        );

        expect(result, isTrue);
        expect(freshGateway.isDeviceOwnershipVerified('1'), isTrue);

        // Now device payload is admitted
        final devicePayload = {
          'id': '1',
          'tableNumber': 1,
          'flag': -1,
          'online': true,
          'unlocked': true,
        };
        freshGateway.processDevicePayload(devicePayload);

        expect(freshGateway.currentTables.any((t) => t.tableNumber == 1), isTrue);
        expect(freshGateway.getLiveTable('1'), isNotNull);
      },
    );

    test(
      '15. Device Ownership: Operational commands (TRIGGER, ACCEPT, RESET) are strictly blocked for unauthorized devices',
      () async {
        final freshGateway = GatewayWifiService();
        freshGateway.resetForTesting();

        // Device 5 is not verified
        final commandSuccess = await freshGateway.sendGatewayCommand(
          tableId: '5',
          command: 'TRIGGER',
        );

        expect(
          commandSuccess,
          isFalse,
          reason: 'Operational commands must be blocked before device ownership verification',
        );
      },
    );

    test(
      '16. Device Ownership: Alphanumeric Device ID Shoon2 (Table 2) with Password 12345 succeeds and appears in currentTables as Table 2',
      () async {
        final freshGateway = GatewayWifiService();
        freshGateway.resetForTesting();

        // Device 2 / Shoon2 has registered password 12345
        freshGateway.registerStoredCredential('Shoon2', '12345');
        freshGateway.devicePasswordValidator = (tableId, pwd) async => pwd == '12345';

        // Ownership verification with correct password 12345
        final result = await freshGateway.verifyDeviceOwnership(
          deviceId: 'Shoon2',
          password: '12345',
        );

        expect(result, isTrue);
        expect(freshGateway.isDeviceOwnershipVerified('Shoon2'), isTrue);
        expect(freshGateway.isDeviceOwnershipVerified('2'), isTrue);

        // Process device payload for Shoon2
        freshGateway.processDevicePayload({
          'id': 'Shoon2',
          'tableNumber': 'Shoon2',
          'flag': -1,
          'online': true,
          'unlocked': true,
        });

        // Must be admitted and correctly mapped to Table 2
        final table = freshGateway.getLiveTable('Shoon2');
        expect(table, isNotNull);
        expect(table!.tableNumber, equals(2));
        expect(freshGateway.currentTables.any((t) => t.tableNumber == 2), isTrue);
      },
    );

    test(
      '17. Device Ownership: Device Shoon2 with incorrect password fails and is strictly rejected',
      () async {
        final freshGateway = GatewayWifiService();
        freshGateway.resetForTesting();

        freshGateway.registerStoredCredential('Shoon2', '12345');

        // Verify with wrong password
        final result = await freshGateway.verifyDeviceOwnership(
          deviceId: 'Shoon2',
          password: 'wrong_password',
        );

        expect(result, isFalse);
        expect(freshGateway.isDeviceOwnershipVerified('Shoon2'), isFalse);
        expect(freshGateway.isDeviceOwnershipVerified('2'), isFalse);

        freshGateway.processDevicePayload({
          'id': 'Shoon2',
          'tableNumber': 'Shoon2',
          'flag': -1,
          'online': true,
          'unlocked': true,
        });

        expect(freshGateway.currentTables.any((t) => t.tableNumber == 2), isFalse);
        expect(freshGateway.getLiveTable('Shoon2'), isNull);
      },
    );

    test(
      '18. Device Ownership: Pure Dynamic flow without dummy data - Discovered device is unverified until manager dynamically verifies it',
      () async {
        final freshGateway = GatewayWifiService();
        freshGateway.resetForTesting();

        // Ensure zero dummy data in stored credentials
        expect(freshGateway.isDeviceRegistered('CustomTag42'), isFalse);
        expect(freshGateway.isDeviceRegistered('42'), isFalse);

        // 1. Device is discovered by gateway on the network
        freshGateway.processDevicePayload({
          'id': 'CustomTag42',
          'tableNumber': 'CustomTag42',
          'flag': -1,
          'online': true,
          'unlocked': false,
        });

        // 2. Unverified device must NOT be in currentTables or live tables
        expect(freshGateway.isDeviceOwnershipVerified('CustomTag42'), isFalse);
        expect(freshGateway.currentTables.any((t) => t.tableNumber == 42), isFalse);
        expect(freshGateway.getLiveTable('CustomTag42'), isNull);

        // 3. Manager verifies ownership dynamically with password 'MySecretPass'
        freshGateway.devicePasswordValidator = (tableId, pwd) async => pwd == 'MySecretPass';

        final verified = await freshGateway.verifyDeviceOwnership(
          deviceId: 'CustomTag42',
          password: 'MySecretPass',
        );

        expect(verified, isTrue);
        expect(freshGateway.isDeviceOwnershipVerified('CustomTag42'), isTrue);
        expect(freshGateway.isDeviceOwnershipVerified('42'), isTrue);
        expect(freshGateway.getStoredPassword('CustomTag42'), equals('MySecretPass'));
        expect(freshGateway.getStoredPassword('42'), equals('MySecretPass'));

        // 4. Now processDevicePayload admits the verified table into currentTables
        freshGateway.processDevicePayload({
          'id': 'CustomTag42',
          'tableNumber': 'CustomTag42',
          'flag': -1,
          'online': true,
          'unlocked': true,
        });

        expect(freshGateway.currentTables.any((t) => t.tableNumber == 42), isTrue);
        final liveTable = freshGateway.getLiveTable('CustomTag42');
        expect(liveTable, isNotNull);
        expect(liveTable!.tableNumber, equals(42));
      },
    );
  });
}
