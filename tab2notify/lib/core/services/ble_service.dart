import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../features/service_requests/domain/table_model.dart';

class BleService {
  // Singleton instance
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // Tab2Notify Service & Characteristic UUIDs
  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String charUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  // Dynamic Table State Map: Only holds actively advertising ESP devices
  final Map<String, TableModel> _tables = {};
  final Map<String, BluetoothDevice> _discoveredDevices = {};
  final Map<String, DateTime> _lastSeenTimes = {};

  final StreamController<List<TableModel>> _tablesController =
      StreamController<List<TableModel>>.broadcast();

  final StreamController<bool> _isScanningController =
      StreamController<bool>.broadcast();

  final StreamController<BluetoothAdapterState> _adapterStateController =
      StreamController<BluetoothAdapterState>.broadcast();

  // Yield actively advertising tables to subscribers
  Stream<List<TableModel>> get tablesStream async* {
    final list = _tables.values.where((t) => t.isDeviceOnline).toList();
    list.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
    yield list;
    yield* _tablesController.stream;
  }

  Stream<bool> get isScanningStream => _isScanningController.stream;
  Stream<BluetoothAdapterState> get adapterStateStream =>
      _adapterStateController.stream;

  Timer? _staleCheckTimer;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _adapterStateSubscription;
  bool _isInitialized = false;

  void _emitTables() {
    final list = _tables.values.where((t) => t.isDeviceOnline).toList();
    list.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
    _tablesController.add(list);
  }

  Future<void> requestPermissionsAndStartScan() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      if (Platform.isAndroid) {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
          Permission.location,
        ].request();
      } else if (Platform.isIOS) {
        await [Permission.bluetooth].request();
      }

      // Listen to adapter state
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
        _adapterStateController.add(state);
        if (state == BluetoothAdapterState.on) {
          startScan();
        }
      });

      // Periodically remove stale/offline devices (every 3 seconds)
      _staleCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _checkStaleDevices();
      });

      final state = await FlutterBluePlus.adapterState.first;
      if (state == BluetoothAdapterState.on) {
        await startScan();
      }
    } catch (e) {
      debugPrint('[BLE] Permission / Setup error: $e');
    }
  }

  Future<void> startScan() async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      _isScanningController.add(true);

      _scanSubscription?.cancel();
      // Real-time low-latency scan results listener
      _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          _processScanResult(r);
        }
      });

      // Low Latency continuous scan
      await FlutterBluePlus.startScan(
        timeout: const Duration(minutes: 30),
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
      );
    } catch (e) {
      debugPrint('[BLE] startScan error: $e');
    }
  }

  void _processScanResult(ScanResult result) {
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : (result.device.advName.isNotEmpty
            ? result.device.advName
            : result.device.platformName);

    final bool hasServiceUuid = result.advertisementData.serviceUuids
        .any((u) => u.toString().toLowerCase().contains(serviceUuid.toLowerCase()));

    // Match only Tab2Notify devices (e.g. T2N_T1_REQ, T2N_T3_IDLE, Table_3, etc.)
    if (name.startsWith('T2N_') ||
        name.startsWith('Table_') ||
        name.contains('Tap2Notify') ||
        hasServiceUuid) {
      int? extractedTableNumber;
      int? detectedFlag;
      String? detectedStatus;
      String? detectedWaiter;

      // 1. Check Un-cached Raw Manufacturer Data FIRST (High Priority for instant 20ms reflection)
      final mfgData = result.advertisementData.manufacturerData;
      if (mfgData.isNotEmpty) {
        for (final entry in mfgData.entries) {
          try {
            final str = utf8.decode(entry.value, allowMalformed: true).trim();
            if (str.contains(':')) {
              final parts = str.split(':');
              if (parts.isNotEmpty) {
                final tNum = int.tryParse(parts[0]);
                if (tNum != null) {
                  extractedTableNumber = tNum;
                }
              }
              if (parts.length > 1) {
                final f = int.tryParse(parts[1]);
                if (f != null) {
                  detectedFlag = f;
                  if (f == 0) detectedStatus = 'pending';
                  if (f == 1) {
                    detectedStatus = 'accepted';
                    if (parts.length > 2) detectedWaiter = parts[2];
                  }
                  if (f == -1) detectedStatus = 'idle';
                }
              }
            } else if (str.contains('{') && str.contains('}')) {
              final json = jsonDecode(str);
              if (json['t'] != null) {
                extractedTableNumber = int.tryParse(json['t'].toString());
              }
              if (json['f'] != null) {
                final f = int.tryParse(json['f'].toString());
                if (f != null) {
                  detectedFlag = f;
                  if (f == 0) detectedStatus = 'pending';
                  if (f == 1) detectedStatus = 'accepted';
                  if (f == -1) detectedStatus = 'idle';
                }
              }
              if (json['s'] != null) detectedStatus = json['s'].toString();
              if (json['w'] != null) detectedWaiter = json['w'].toString();
            }
          } catch (_) {}
        }
      }

      // 2. Extract Table Number from Device Name if not found in payload
      if (extractedTableNumber == null) {
        final match = RegExp(r'T2N_(?:Table_|T)(\d+)', caseSensitive: false).firstMatch(name) ??
                      RegExp(r'Table_(\d+)', caseSensitive: false).firstMatch(name) ??
                      RegExp(r'_T(\d+)', caseSensitive: false).firstMatch(name);
        if (match != null) {
          extractedTableNumber = int.tryParse(match.group(1) ?? '1');
        }
      }

      // 3. Fallback to Device Name status ONLY if Manufacturer Data was absent
      if (detectedFlag == null) {
        if (name.contains('_REQ') || name.contains('PENDING')) {
          detectedFlag = 0;
          detectedStatus = 'pending';
        } else if (name.contains('_ACC') || name.contains('ACCEPTED') || name.contains('_OK')) {
          detectedFlag = 1;
          detectedStatus = 'accepted';
        } else if (name.contains('_IDLE')) {
          detectedFlag = -1;
          detectedStatus = 'idle';
        }
      }

      final tableNum = extractedTableNumber ?? 1;
      final tableId = 'table_$tableNum';

      _discoveredDevices[tableId] = result.device;
      _lastSeenTimes[tableId] = DateTime.now();

      final existing = _tables[tableId];
      final finalFlag = detectedFlag ?? (existing?.flag ?? -1);
      final finalStatus = detectedStatus ?? (finalFlag == 0 ? 'pending' : (finalFlag == 1 ? 'accepted' : 'idle'));
      final finalWaiter = detectedWaiter ?? (existing?.waiterName ?? '');

      _tables[tableId] = TableModel(
        id: tableId,
        tableNumber: tableNum,
        deviceId: 'device_$tableNum',
        status: finalStatus,
        flag: finalFlag,
        waiterName: finalWaiter,
        isDeviceOnline: true,
        createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      _emitTables();
    }
  }

  // Remove devices that stopped advertising (> 8 seconds) so ONLY active advertising tables show
  void _checkStaleDevices() {
    final now = DateTime.now();
    final List<String> staleIds = [];

    _lastSeenTimes.forEach((tableId, lastSeen) {
      if (now.difference(lastSeen).inSeconds > 8) {
        staleIds.add(tableId);
      }
    });

    if (staleIds.isNotEmpty) {
      for (final id in staleIds) {
        _tables.remove(id);
        _discoveredDevices.remove(id);
        _lastSeenTimes.remove(id);
      }
      _emitTables();
    }
  }

  // Manager Accepts Request: Connects via BLE & writes flag = 1
  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? managerUid,
  }) async {
    final current = _tables[tableId];
    if (current != null) {
      _tables[tableId] = current.copyWith(
        flag: 1,
        status: 'accepted',
        waiterName: waiterName,
        acceptedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _emitTables();
    }

    final device = _discoveredDevices[tableId];
    if (device != null) {
      try {
        debugPrint('[BLE] Connecting to ${device.remoteId} for $tableId...');
        await device.connect(timeout: const Duration(seconds: 4));

        final services = await device.discoverServices();
        for (final s in services) {
          if (s.uuid.toString().toLowerCase().contains(serviceUuid.toLowerCase())) {
            for (final c in s.characteristics) {
              if (c.uuid.toString().toLowerCase().contains(charUuid.toLowerCase())) {
                final payload = jsonEncode({
                  'flag': 1,
                  'status': 'accepted',
                  'waiter': waiterName,
                });
                await c.write(utf8.encode(payload), withoutResponse: false);
                debugPrint('[BLE] Sent acceptance to $tableId: $payload');
                break;
              }
            }
          }
        }
        await device.disconnect();
      } catch (e) {
        debugPrint('[BLE] Error sending accept command: $e');
      }
    }
  }

  Future<void> resetTableStatus(String tableId) async {
    final current = _tables[tableId];
    if (current != null) {
      _tables[tableId] = current.copyWith(
        flag: -1,
        status: 'idle',
        waiterName: '',
      );
      _emitTables();
    }

    final device = _discoveredDevices[tableId];
    if (device != null) {
      try {
        await device.connect(timeout: const Duration(seconds: 3));
        final services = await device.discoverServices();
        for (final s in services) {
          if (s.uuid.toString().toLowerCase().contains(serviceUuid.toLowerCase())) {
            for (final c in s.characteristics) {
              if (c.uuid.toString().toLowerCase().contains(charUuid.toLowerCase())) {
                final payload = jsonEncode({'flag': -1, 'status': 'idle'});
                await c.write(utf8.encode(payload), withoutResponse: false);
                break;
              }
            }
          }
        }
        await device.disconnect();
      } catch (_) {}
    }
  }

  Future<void> triggerTableRequest(String tableId, {int? tableNumber}) async {
    final current = _tables[tableId];
    final num = tableNumber ?? (current?.tableNumber ?? 1);
    final now = DateTime.now().millisecondsSinceEpoch;

    _tables[tableId] = TableModel(
      id: tableId,
      tableNumber: num,
      deviceId: 'device_$num',
      status: 'pending',
      flag: 0,
      waiterName: '',
      isDeviceOnline: true,
      createdAt: now,
      updatedAt: now,
    );
    _emitTables();
  }

  void dispose() {
    _staleCheckTimer?.cancel();
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _tablesController.close();
    _isScanningController.close();
    _adapterStateController.close();
  }
}
