import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/core/services/ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BLE Scan Result & Status Detection Tests', () {
    late BleService bleService;

    setUp(() {
      bleService = BleService();
    });

    test('Primary advertisement with REQ sets Table 2 to pending (flag: 0)', () {
      final device = BluetoothDevice(remoteId: const DeviceIdentifier('AA:BB:CC:DD:EE:02'));
      final advData = AdvertisementData(
        advName: 'T2N_T2_REQ',
        txPowerLevel: null,
        connectable: true,
        manufacturerData: {
          0x3A32: [0x30, 0x3A, 0x31], // "2:" key with "0:1" value -> "2:0:1"
        },
        serviceData: {},
        serviceUuids: [Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b')],
        appearance: null,
      );

      final result = ScanResult(
        device: device,
        advertisementData: advData,
        rssi: -60,
        timeStamp: DateTime.now(),
      );

      bleService.processScanResultForTesting(result);

      final table = bleService.getLiveBleTable('table_2');
      expect(table, isNotNull);
      expect(table!.tableNumber, 2);
      expect(table.flag, 0);
      expect(table.status, 'pending');
      expect(table.isPending, isTrue);
      expect(table.isAccepted, isFalse);
    });

    test('Primary advertisement with IDLE sets Table 2 to idle (flag: -1)', () {
      final device = BluetoothDevice(remoteId: const DeviceIdentifier('AA:BB:CC:DD:EE:02'));
      final advData = AdvertisementData(
        advName: 'T2N_T2_IDLE',
        txPowerLevel: null,
        connectable: true,
        manufacturerData: {
          0x3A32: [0x2D, 0x31, 0x3A, 0x32], // "2:" key with "-1:2" value -> "2:-1:2"
        },
        serviceData: {},
        serviceUuids: [Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b')],
        appearance: null,
      );

      final result = ScanResult(
        device: device,
        advertisementData: advData,
        rssi: -60,
        timeStamp: DateTime.now(),
      );

      bleService.processScanResultForTesting(result);

      final table = bleService.getLiveBleTable('table_2');
      expect(table, isNotNull);
      expect(table!.flag, -1);
      expect(table.status, 'idle');
      expect(table.isIdle, isTrue);
      expect(table.isAccepted, isFalse);
    });

    test('Scan Response packet with empty advName and cached platformName does NOT force table to accepted', () {
      // Table 2 is currently IDLE
      expect(bleService.getLiveBleTable('table_2')?.flag, -1);

      // A scan response packet arrives with empty advName and no mfgData
      final device = BluetoothDevice(remoteId: const DeviceIdentifier('AA:BB:CC:DD:EE:02'));
      final scanResponseData = AdvertisementData(
        advName: '',
        txPowerLevel: null,
        connectable: true,
        manufacturerData: {},
        serviceData: {},
        serviceUuids: [Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b')],
        appearance: null,
      );

      final scanResponseResult = ScanResult(
        device: device,
        advertisementData: scanResponseData,
        rssi: -62,
        timeStamp: DateTime.now(),
      );

      bleService.processScanResultForTesting(scanResponseResult);

      // Table 2 MUST remain idle and NOT be forced to accepted
      final table = bleService.getLiveBleTable('table_2');
      expect(table, isNotNull);
      expect(table!.flag, -1);
      expect(table.status, 'idle');
      expect(table.isAccepted, isFalse);
    });

    test('Resetting Table 2 via resetTableStatus stays idle when scan response packet arrives', () async {
      await bleService.resetTableStatus('table_2');
      expect(bleService.getLiveBleTable('table_2')?.flag, -1);

      // Empty scan response packet arrives
      final device = BluetoothDevice(remoteId: const DeviceIdentifier('AA:BB:CC:DD:EE:02'));
      final scanResponseData = AdvertisementData(
        advName: '',
        txPowerLevel: null,
        connectable: true,
        manufacturerData: {},
        serviceData: {},
        serviceUuids: [Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b')],
        appearance: null,
      );

      final scanResponseResult = ScanResult(
        device: device,
        advertisementData: scanResponseData,
        rssi: -62,
        timeStamp: DateTime.now(),
      );

      bleService.processScanResultForTesting(scanResponseResult);

      expect(bleService.getLiveBleTable('table_2')?.flag, -1);
      expect(bleService.getLiveBleTable('table_2')?.status, 'idle');
    });

    test('resetAllTables resets all tracked tables to idle (flag: -1)', () async {
      // First, set table 2 to accepted
      await bleService.acceptTableRequest(tableId: 'table_2', waiterName: 'Rahul');
      expect(bleService.getLiveBleTable('table_2')?.isAccepted, isTrue);

      // Now reset all
      await bleService.resetAllTables();
      expect(bleService.getLiveBleTable('table_2')?.flag, -1);
      expect(bleService.getLiveBleTable('table_2')?.status, 'idle');
      expect(bleService.getLiveBleTable('table_2')?.waiterName, '');
    });

    test('Flexible device names (T2N-T3-REQ, Table_4_CALL) parse correctly', () {
      final device = BluetoothDevice(remoteId: const DeviceIdentifier('AA:BB:CC:DD:EE:03'));
      final advData = AdvertisementData(
        advName: 'T2N-T3-REQ',
        txPowerLevel: null,
        connectable: true,
        manufacturerData: {},
        serviceData: {},
        serviceUuids: [Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b')],
        appearance: null,
      );

      final result = ScanResult(
        device: device,
        advertisementData: advData,
        rssi: -55,
        timeStamp: DateTime.now(),
      );

      bleService.processScanResultForTesting(result);

      final table = bleService.getLiveBleTable('table_3');
      expect(table, isNotNull);
      expect(table!.tableNumber, 3);
      expect(table.flag, 0);
      expect(table.status, 'pending');
      expect(table.isPending, isTrue);
    });

    test('Flexible lookup by numeric string "3" finds "table_3" and online status', () {
      expect(bleService.getLiveBleTable('3')?.tableNumber, 3);
      expect(bleService.isTableOnline('3'), isTrue);
      expect(bleService.isTableOnline('table_3'), isTrue);
    });

    test('Foreign non-Tap2Notify Bluetooth devices (Apple, Microsoft, generic beacons) are strictly ignored', () {
      // Apple device (0x004C) with random bytes
      final appleDevice = BluetoothDevice(remoteId: const DeviceIdentifier('FF:EE:DD:CC:BB:AA'));
      final appleAdvData = AdvertisementData(
        advName: '',
        txPowerLevel: null,
        connectable: true,
        manufacturerData: {
          0x004C: [0x02, 0x15, 0x01, 0x00], // 0x4C = 76 in decimal
        },
        serviceData: {},
        serviceUuids: [],
        appearance: null,
      );

      final appleResult = ScanResult(
        device: appleDevice,
        advertisementData: appleAdvData,
        rssi: -70,
        timeStamp: DateTime.now(),
      );

      bleService.processScanResultForTesting(appleResult);
      expect(bleService.getLiveBleTable('table_76'), isNull);

      // Microsoft PC beacon (0x0006)
      final msDevice = BluetoothDevice(remoteId: const DeviceIdentifier('11:22:33:44:55:66'));
      final msAdvData = AdvertisementData(
        advName: 'DESKTOP-XYZ',
        txPowerLevel: null,
        connectable: true,
        manufacturerData: {
          0x0006: [0x01, 0x00, 0x03],
        },
        serviceData: {},
        serviceUuids: [],
        appearance: null,
      );

      final msResult = ScanResult(
        device: msDevice,
        advertisementData: msAdvData,
        rssi: -50,
        timeStamp: DateTime.now(),
      );

      bleService.processScanResultForTesting(msResult);
      expect(bleService.getLiveBleTable('table_6'), isNull);
    });
  });
}
