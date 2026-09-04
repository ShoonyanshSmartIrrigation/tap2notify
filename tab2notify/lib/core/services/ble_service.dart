import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  // Callbacks for database sync
  void Function(TableModel table)? onDeviceDiscovered;
  void Function(String tableId)? onDeviceLost;

  // Yield actively advertising tables to subscribers
  Stream<List<TableModel>> get tablesStream async* {
    yield currentTables;
    yield* _tablesController.stream;
  }

  List<TableModel> get currentTables {
    final list = _tables.values.where((t) => isTableOnline(t.id)).toList();
    list.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
    return list;
  }

  bool isTableOnline(String tableId) {
    final lastSeen = _lastSeenTimes[tableId];
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen).inSeconds <= 20;
  }

  TableModel? getLiveBleTable(String tableId) {
    return _tables[tableId];
  }

  Stream<bool> get isScanningStream => _isScanningController.stream;
  Stream<BluetoothAdapterState> get adapterStateStream =>
      _adapterStateController.stream;

  Timer? _staleCheckTimer;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _adapterStateSubscription;
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  void _emitTables() {
    _tablesController.add(currentTables);
  }

  Future<void> requestPermissionsAndStartScan() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        debugPrint('[BLE] Bluetooth Low Energy is not supported on this platform.');
        return;
      }

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

      // Periodically remove stale/offline devices (every 3 seconds)
      _staleCheckTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
        _checkStaleDevices();
      });

      // Listen to adapter state changes
      _adapterStateSubscription ??= FlutterBluePlus.adapterState.listen((state) {
        _adapterStateController.add(state);
        debugPrint('[BLE] Bluetooth Adapter State: $state');
        if (state == BluetoothAdapterState.on) {
          startScan();
        }
      });

      final state = await FlutterBluePlus.adapterState.first;
      if (state == BluetoothAdapterState.on) {
        await startScan();
      } else if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[BLE] Permission / Setup error: $e');
    }
  }

  Future<void> startScan() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return;

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      _isScanning = true;
      _isScanningController.add(true);

      _scanSubscription?.cancel();
      // Single unbuffered low-latency stream listener (Zero frame drops)
      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        (results) {
          for (final r in results) {
            _processScanResult(r);
          }
        },
        onError: (err) {
          debugPrint('[BLE] onScanResults error: $err');
        },
      );

      // Low Latency continuous scan with fine location
      await FlutterBluePlus.startScan(
        timeout: const Duration(minutes: 30),
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: true,
        continuousUpdates: true,
      );
    } catch (e) {
      debugPrint('[BLE] startScan error: $e');
    } finally {
      _isScanning = false;
      _isScanningController.add(false);
    }
  }

  void _processScanResult(ScanResult result) {
    final advName = result.advertisementData.advName;
    final deviceAdvName = result.device.advName;
    final platformName = result.device.platformName;

    // Resolve name from any available source
    final String name = advName.isNotEmpty
        ? advName
        : (deviceAdvName.isNotEmpty ? deviceAdvName : platformName);

    final bool hasServiceUuid = result.advertisementData.serviceUuids
        .any((u) => u.toString().toLowerCase().contains(serviceUuid.toLowerCase()));

    final mfgData = result.advertisementData.manufacturerData;
    final bool hasCustomMfgData = mfgData.containsKey(0xFFFF);

    // Match criteria strictly for genuine Tab2Notify ESP32 devices
    final bool isMatchingDevice = name.startsWith('T2N_') ||
        name.startsWith('Table_') ||
        name.startsWith('Table-') ||
        name.contains('Tap2Notify') ||
        hasServiceUuid ||
        hasCustomMfgData;

    if (!isMatchingDevice) return;

    int? extractedTableNumber;
    int? detectedFlag;
    String? detectedStatus;
    String? detectedWaiter;

    // 1. Process Manufacturer Data strictly for our 0xFFFF custom company identifier
    if (mfgData.containsKey(0xFFFF)) {
      final List<int> valBytes = mfgData[0xFFFF] ?? [];
      if (valBytes.isNotEmpty) {
        try {
          final String valStr = String.fromCharCodes(valBytes).trim();

          // Strategy 1: ASCII Separated Payload (e.g. "1:0" or "1:0:12")
          if (valStr.contains(':')) {
            final parts = valStr.split(':');
            if (parts.length >= 2) {
              final tNum = int.tryParse(parts[0].replaceAll(RegExp(r'[^0-9]'), ''));
              final f = int.tryParse(parts[1].trim());
              if (tNum != null && tNum > 0 && tNum <= 100) extractedTableNumber = tNum;
              if (f != null) {
                detectedFlag = f;
                if (f == 0) detectedStatus = 'pending';
                if (f == 1) detectedStatus = 'accepted';
                if (f == -1) detectedStatus = 'idle';
              }
            }
          }

          // Strategy 2: Binary Protocol [TableNum, Flag, Sequence]
          if (detectedFlag == null && valBytes.length >= 2) {
            final tNum = valBytes[0];
            final rawFlag = valBytes[1];
            if (tNum > 0 && tNum <= 100) {
              extractedTableNumber = tNum;
              if (rawFlag == 0) {
                detectedFlag = 0;
                detectedStatus = 'pending';
              } else if (rawFlag == 1) {
                detectedFlag = 1;
                detectedStatus = 'accepted';
              } else if (rawFlag == 0xFF || rawFlag == 255 || rawFlag == -1) {
                detectedFlag = -1;
                detectedStatus = 'idle';
              }
            }
          }

          // Strategy 3: JSON Payload
          if (detectedFlag == null && valStr.contains('{')) {
            final json = jsonDecode(valStr);
            if (json['t'] != null) {
              final parsed = int.tryParse(json['t'].toString());
              if (parsed != null && parsed > 0 && parsed <= 100) {
                extractedTableNumber = parsed;
              }
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
          }
        } catch (_) {}
      }
    }

    // 2. Extract Table Number strictly from Tab2Notify Device Names
    if (extractedTableNumber == null && name.isNotEmpty) {
      final match = RegExp(r'T2N_(?:Table_|T)?(\d+)', caseSensitive: false).firstMatch(name) ??
                    RegExp(r'Table[_-](\d+)', caseSensitive: false).firstMatch(name) ??
                    RegExp(r'Tap2Notify[_-](\d+)', caseSensitive: false).firstMatch(name);
      if (match != null) {
        final parsed = int.tryParse(match.group(1) ?? '');
        if (parsed != null && parsed > 0 && parsed <= 100) {
          extractedTableNumber = parsed;
        }
      }
    }

    // If no legitimate table number was determined, do NOT process this foreign device!
    if (extractedTableNumber == null || extractedTableNumber <= 0 || extractedTableNumber > 100) {
      return;
    }

    // 3. Fallback to Device Name status (e.g. T2N_T1_REQ, T2N_T1_ACC, T2N_T1_IDLE)
    if (detectedFlag == null && name.isNotEmpty) {
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

    final tableNum = extractedTableNumber;
    final tableId = 'table_$tableNum';

    _discoveredDevices[tableId] = result.device;
    _lastSeenTimes[tableId] = DateTime.now();

    final existing = _tables[tableId];
    final finalFlag = detectedFlag ?? (existing?.flag ?? -1);
    final finalStatus = detectedStatus ??
        (finalFlag == 0 ? 'pending' : (finalFlag == 1 ? 'accepted' : 'idle'));
    final finalWaiter = detectedWaiter ?? (existing?.waiterName ?? '');

    final bool stateChanged = existing == null ||
        existing.flag != finalFlag ||
        existing.status != finalStatus ||
        existing.isDeviceOnline != true;

    final updatedTable = TableModel(
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

    _tables[tableId] = updatedTable;

    // Trigger state-transition hooks, instant UI emission, and cloud sync ONLY when state changes
    if (stateChanged) {
      _emitTables();

      debugPrint('[BLE INSTANT] Table $tableNum STATE CHANGED -> Flag: $finalFlag ($finalStatus)');
      if (finalFlag == 0) {
        try {
          HapticFeedback.heavyImpact();
        } catch (_) {}
      }

      // Asynchronous background cloud sync
      onDeviceDiscovered?.call(updatedTable);
    }
  }

  // Remove devices that stopped advertising (> 15 seconds)
  void _checkStaleDevices() {
    final now = DateTime.now();
    final List<String> staleIds = [];

    _lastSeenTimes.forEach((tableId, lastSeen) {
      if (now.difference(lastSeen).inSeconds > 15) {
        staleIds.add(tableId);
      }
    });

    if (staleIds.isNotEmpty) {
      for (final id in staleIds) {
        _tables.remove(id);
        _discoveredDevices.remove(id);
        _lastSeenTimes.remove(id);
        onDeviceLost?.call(id);
      }
      _emitTables();
    }
  }

  // Manager Accepts Request: Updates App State to ACCEPTED
  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? managerUid,
  }) async {
    final current = _tables[tableId];
    if (current != null) {
      final updated = current.copyWith(
        flag: 1,
        status: 'accepted',
        waiterName: waiterName,
        acceptedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _tables[tableId] = updated;
      _emitTables();
      onDeviceDiscovered?.call(updated);
    }
  }

  // Manager Completes/Resets Request: Updates App State to IDLE
  Future<void> resetTableStatus(String tableId) async {
    final current = _tables[tableId];
    if (current != null) {
      final updated = current.copyWith(
        flag: -1,
        status: 'idle',
        waiterName: '',
      );
      _tables[tableId] = updated;
      _emitTables();
      onDeviceDiscovered?.call(updated);
    }
  }

  Future<void> triggerTableRequest(String tableId, {int? tableNumber}) async {
    final current = _tables[tableId];
    final num = tableNumber ?? (current?.tableNumber ?? 1);
    final now = DateTime.now().millisecondsSinceEpoch;

    final updated = TableModel(
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
    _tables[tableId] = updated;
    _emitTables();
    onDeviceDiscovered?.call(updated);
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
