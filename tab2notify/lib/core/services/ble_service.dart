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
  Stream<List<TableModel>> get tablesStream => _tablesController.stream;

  List<TableModel> get currentTables {
    final list = _tables.values.where((t) => isTableOnline(t.id)).toList();
    list.sort((a, b) {
      final aNum = int.tryParse(a.tableNumber.toString());
      final bNum = int.tryParse(b.tableNumber.toString());
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }
      return a.tableNumber.toString().compareTo(b.tableNumber.toString());
    });
    return list;
  }

  bool isTableOnline(String tableId) {
    if (_lastSeenTimes.containsKey(tableId)) {
      return DateTime.now().difference(_lastSeenTimes[tableId]!).inSeconds <= 20;
    }
    final rawId = tableId.startsWith('table_') ? tableId.substring(6) : tableId;
    if (_lastSeenTimes.containsKey('table_$rawId')) {
      return DateTime.now().difference(_lastSeenTimes['table_$rawId']!).inSeconds <= 20;
    }
    return false;
  }

  TableModel? getLiveBleTable(String tableId) {
    if (_tables.containsKey(tableId)) return _tables[tableId];
    final rawId = tableId.startsWith('table_') ? tableId.substring(6) : tableId;
    return _tables['table_$rawId'] ??
        _tables.values.cast<TableModel?>().firstWhere(
              (t) =>
                  t?.tableNumber.toString() == tableId ||
                  t?.tableNumber.toString() == rawId,
              orElse: () => null,
            );
  }

  Stream<bool> get isScanningStream => FlutterBluePlus.isScanning;
  Stream<BluetoothAdapterState> get adapterStateStream => FlutterBluePlus.adapterState;
  bool get isScanning => FlutterBluePlus.isScanningNow;

  Timer? _staleCheckTimer;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _adapterStateSubscription;

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

      // Periodically check for stale/offline devices (every 3 seconds)
      _staleCheckTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
        _checkStaleDevices();
      });

      // Listen to adapter state changes and auto start scan when turned on
      _adapterStateSubscription ??= FlutterBluePlus.adapterState.listen((state) {
        debugPrint('[BLE] Bluetooth Adapter State: $state');
        if (state == BluetoothAdapterState.on && !FlutterBluePlus.isScanningNow) {
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

      // Low Latency continuous scan with continuous updates
      await FlutterBluePlus.startScan(
        timeout: const Duration(days: 365),
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: false,
        continuousUpdates: true,
      );
    } catch (e) {
      debugPrint('[BLE] startScan error: $e');
    }
  }

  @visibleForTesting
  void processScanResultForTesting(ScanResult result) => _processScanResult(result);

  void _processScanResult(ScanResult result) {
    final advName = result.advertisementData.advName;
    final deviceAdvName = result.device.advName;
    final platformName = result.device.platformName;

    // Resolve name from any available source
    final String name = advName.isNotEmpty
        ? advName
        : (deviceAdvName.isNotEmpty ? deviceAdvName : platformName);

    final String upperName = name.toUpperCase();
    final bool hasServiceUuid = result.advertisementData.serviceUuids
        .any((u) => u.toString().toLowerCase().contains(serviceUuid.toLowerCase()));

    // Match criteria strictly for genuine Tab2Notify ESP32 devices
    final bool isMatchingDevice = upperName.startsWith('T2N') ||
        upperName.startsWith('TABLE') ||
        upperName.contains('TAP2NOTIFY') ||
        hasServiceUuid;

    if (!isMatchingDevice) return;

    final mfgData = result.advertisementData.manufacturerData;

    dynamic extractedTableNumber;
    int? detectedFlag;
    String? detectedStatus;
    String? detectedWaiter;

    // 1. Process Manufacturer Data across all company identifiers
    // (In ESP32 Arduino, setManufacturerData(str) places the first 2 ASCII chars into the 16-bit key)
    if (mfgData.isNotEmpty) {
      for (final entry in mfgData.entries) {
        final key = entry.key;
        final valBytes = entry.value;

        // Reconstruct both:
        // A) Combined string: Key (2 bytes little-endian) + value bytes
        final keyChars = String.fromCharCodes([key & 0xFF, (key >> 8) & 0xFF]);
        final rawValStr = String.fromCharCodes(valBytes).trim();
        final combinedStr = '$keyChars$rawValStr'.trim();

        for (final candidate in [combinedStr, rawValStr]) {
          // Strategy 1: Delimited Payload (e.g. "2:0:1", "2,0,1", "2;0;1", "2:0", "2 -1 3", "A1:0:1")
          if (candidate.contains(':') || candidate.contains(',') || candidate.contains(';') || candidate.contains('-')) {
            final parts = candidate.split(RegExp(r'[:,;\s]')).where((s) => s.isNotEmpty).toList();
            if (parts.length >= 2) {
              final tNum = parts[0].trim();
              final f = int.tryParse(parts[1].trim());
              if (tNum.isNotEmpty) {
                final asInt = int.tryParse(tNum);
                extractedTableNumber = asInt ?? tNum;
              }
              if (f != null) {
                detectedFlag = f;
                if (f == 0) detectedStatus = 'pending';
                if (f == 1) detectedStatus = 'accepted';
                if (f == -1) detectedStatus = 'idle';
                break;
              }
            }
          }

          // Strategy 2: JSON Payload
          if (detectedFlag == null && candidate.contains('{')) {
            try {
              final json = jsonDecode(candidate);
              if (json['t'] != null) {
                final parsedStr = json['t'].toString().trim();
                final asInt = int.tryParse(parsedStr);
                if (parsedStr.isNotEmpty) {
                  extractedTableNumber = asInt ?? parsedStr;
                }
              }
              if (json['f'] != null) {
                final f = int.tryParse(json['f'].toString());
                if (f != null) {
                  detectedFlag = f;
                  if (f == 0) detectedStatus = 'pending';
                  if (f == 1) detectedStatus = 'accepted';
                  if (f == -1) detectedStatus = 'idle';
                  break;
                }
              }
            } catch (_) {}
          }
        }

        if (detectedFlag != null) break;

        // Strategy 3: Binary Protocol [TableNum, Flag, Sequence]
        // Guard: Only execute if payload was NOT an ASCII string
        if (detectedFlag == null && !rawValStr.contains(':') && !rawValStr.contains(',')) {
          final combinedBytes = [key & 0xFF, (key >> 8) & 0xFF, ...valBytes];
          for (final bytes in [combinedBytes, valBytes]) {
            if (bytes.length >= 2) {
              final tNum = bytes[0];
              final rawFlag = bytes[1];
              if (tNum > 0 && tNum <= 100) {
                extractedTableNumber = tNum;
                if (rawFlag == 0) {
                  detectedFlag = 0;
                  detectedStatus = 'pending';
                  break;
                } else if (rawFlag == 1) {
                  detectedFlag = 1;
                  detectedStatus = 'accepted';
                  break;
                } else if (rawFlag == 0xFF || rawFlag == 255 || rawFlag == -1) {
                  detectedFlag = -1;
                  detectedStatus = 'idle';
                  break;
                }
              }
            }
          }
        }

        if (detectedFlag != null) break;
      }
    }

    // 2. Extract Table Number strictly from Tab2Notify Device Names
    if (extractedTableNumber == null && name.isNotEmpty) {
      final match = RegExp(r'T2N[_-]?(?:Table[_-]?|T)?([a-zA-Z0-9]+)', caseSensitive: false).firstMatch(name) ??
                    RegExp(r'Table[_-]?([a-zA-Z0-9]+)', caseSensitive: false).firstMatch(name) ??
                    RegExp(r'Tap2Notify[_-]?([a-zA-Z0-9]+)', caseSensitive: false).firstMatch(name) ??
                    RegExp(r'(?:REQ|ACC|IDLE)[_-]?(?:T)?([a-zA-Z0-9]+)', caseSensitive: false).firstMatch(name);
      if (match != null) {
        final parsed = match.group(1)?.trim();
        if (parsed != null && parsed.isNotEmpty) {
          final upperParsed = parsed.toUpperCase();
          if (upperParsed != 'REQ' && upperParsed != 'ACC' && upperParsed != 'IDLE') {
            final asInt = int.tryParse(parsed);
            extractedTableNumber = asInt ?? parsed;
          }
        }
      }
    }

    // If no legitimate table number was determined, do NOT process this foreign device!
    if (extractedTableNumber == null || extractedTableNumber.toString().isEmpty) {
      return;
    }

    // 3. Fallback to LIVE Advertisement Name status (e.g. T2N_T1_REQ, T2N_T1_ACC, T2N_T1_IDLE)
    // Inspect live advertised packet name (advName or deviceAdvName)
    if (detectedFlag == null) {
      final liveName = advName.isNotEmpty ? advName : deviceAdvName;
      if (liveName.isNotEmpty) {
        final upper = liveName.toUpperCase();
        if (upper.contains('REQ') ||
            upper.contains('PEND') ||
            upper.contains('CALL') ||
            upper.contains('HELP') ||
            upper.contains('RED') ||
            upper.contains('ALERT')) {
          detectedFlag = 0;
          detectedStatus = 'pending';
        } else if (upper.contains('ACC') ||
            upper.contains('GREEN') ||
            upper.contains('SERVE') ||
            upper.contains('CONFIRM') ||
            upper.contains('OK')) {
          detectedFlag = 1;
          detectedStatus = 'accepted';
        } else if (upper.contains('IDLE') ||
            upper.contains('STANDBY') ||
            upper.contains('READY') ||
            upper.contains('CLEAR') ||
            upper.contains('OFF') ||
            upper.contains('DONE')) {
          detectedFlag = -1;
          detectedStatus = 'idle';
        }
      }
    }

    final tableNum = extractedTableNumber;
    final tableId = 'table_$tableNum';

    _discoveredDevices[tableId] = result.device;
    _lastSeenTimes[tableId] = DateTime.now();

    final existing = _tables[tableId];

    // If this packet contained no status payload (e.g. Scan Response packet):
    // Preserve existing table state without altering flag or defaulting to accepted.
    if (detectedFlag == null) {
      if (existing != null) {
        // Device is transmitting; ensure online presence without altering status
        if (!existing.isDeviceOnline) {
          final onlineTable = existing.copyWith(isDeviceOnline: true);
          _tables[tableId] = onlineTable;
          _emitTables();
        }
        return;
      }
      // Newly discovered table with unknown status defaults strictly to IDLE (-1)
      detectedFlag = -1;
      detectedStatus = 'idle';
    }

    final finalFlag = detectedFlag;
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

  // Reset all tracked tables back to IDLE
  Future<void> resetAllTables() async {
    final updatedMap = <String, TableModel>{};
    _tables.forEach((key, table) {
      final updated = table.copyWith(
        flag: -1,
        status: 'idle',
        waiterName: '',
      );
      updatedMap[key] = updated;
      onDeviceDiscovered?.call(updated);
    });
    _tables.clear();
    _tables.addAll(updatedMap);
    _emitTables();
  }

  Future<void> triggerTableRequest(String tableId, {dynamic tableNumber}) async {
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
