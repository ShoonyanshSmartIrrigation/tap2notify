import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/service_requests/domain/table_model.dart';

enum GatewayConnectionStatus {
  disconnected,
  discovering,
  connecting,
  connected,
}

class GatewayWifiService {
  // Singleton instance
  static final GatewayWifiService _instance = GatewayWifiService._internal();
  factory GatewayWifiService() => _instance;
  GatewayWifiService._internal();

  // Gateway Network Configurations
  static const String defaultGatewayIp = '192.168.4.1';
  static const int defaultGatewayPort = 80;
  static const int udpDiscoveryPort = 8888;
  static const String mdnsHostname = 'tap2notify.local';
  static const String _prefKeyGatewayIp = 'cached_gateway_ip';

  String _gatewayIp = defaultGatewayIp;
  int _gatewayPort = defaultGatewayPort;
  GatewayConnectionStatus _connectionStatus =
      GatewayConnectionStatus.disconnected;

  // Dynamic Table State Map: Holds all registered table devices from Gateway
  final Map<String, TableModel> _tables = {};
  final Map<String, DateTime> _lastSeenTimes = {};
  final Set<String> _unlockedTableIds = {};

  // Device Ownership Credentials & Verification Tracking (Dynamic, persisted)
  static const String _prefKeyDeviceCredentials = 'gateway_device_credentials';
  final Map<String, String> _storedCredentials = {};
  final Set<String> _verifiedDeviceIds = {};
  final Set<String> _unauthorizedDeviceIds = {};
  final Set<String> _verifyingDeviceIds = {};

  Set<String> get verifiedDeviceIds => Set.unmodifiable(_verifiedDeviceIds);
  bool isDeviceOwnershipVerified(String deviceId) {
    final clean = _cleanTableNum(deviceId);
    final numPart = _extractNumericId(clean);
    return _verifiedDeviceIds.contains(clean) ||
        (numPart != null && _verifiedDeviceIds.contains(numPart));
  }

  bool isDeviceRegistered(String deviceId) {
    final clean = _cleanTableNum(deviceId);
    final numPart = _extractNumericId(clean);
    return _storedCredentials.containsKey(clean) ||
        (numPart != null && _storedCredentials.containsKey(numPart));
  }

  String? getStoredPassword(String deviceId) {
    final clean = _cleanTableNum(deviceId);
    final numPart = _extractNumericId(clean);
    return _storedCredentials[clean] ??
        (numPart != null ? _storedCredentials[numPart] : null);
  }

  void registerStoredCredential(String deviceId, String password) {
    final clean = _cleanTableNum(deviceId);
    final numPart = _extractNumericId(clean);
    final trimmed = password.trim();
    _storedCredentials[clean] = trimmed;
    if (numPart != null) {
      _storedCredentials[numPart] = trimmed;
    }
    _saveStoredCredentials();
  }

  Future<void> _loadStoredCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKeyDeviceCredentials);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final dynamic decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (value != null) {
              _storedCredentials[key.toString()] = value.toString();
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveStoredCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKeyDeviceCredentials,
        jsonEncode(_storedCredentials),
      );
    } catch (_) {}
  }

  @visibleForTesting
  void markDeviceVerifiedForTesting(String deviceId) {
    final clean = _cleanTableNum(deviceId);
    final numPart = _extractNumericId(clean);
    _verifiedDeviceIds.add(clean);
    _unauthorizedDeviceIds.remove(clean);
    if (numPart != null) {
      _verifiedDeviceIds.add(numPart);
      _unauthorizedDeviceIds.remove(numPart);
    }
  }

  /// Optional custom/device password validator callback (e.g. for unit tests)
  Future<bool> Function(String tableId, String password)?
  devicePasswordValidator;

  final StreamController<List<TableModel>> _tablesController =
      StreamController<List<TableModel>>.broadcast();

  final StreamController<bool> _isScanningController =
      StreamController<bool>.broadcast();

  final StreamController<GatewayConnectionStatus> _connectionStatusController =
      StreamController<GatewayConnectionStatus>.broadcast();

  // Callbacks for database sync
  void Function(TableModel table)? onDeviceDiscovered;
  void Function(String tableId)? onDeviceLost;

  // Streams & Getters
  Stream<List<TableModel>> get tablesStream => _tablesController.stream;
  Stream<bool> get isScanningStream => _isScanningController.stream;
  Stream<GatewayConnectionStatus> get connectionStatusStream =>
      _connectionStatusController.stream;

  bool get isConnected =>
      _connectionStatus == GatewayConnectionStatus.connected;
  bool get isScanning => _isScanning;
  bool _isScanning = false;

  String get gatewayIp => _gatewayIp;
  int get gatewayPort => _gatewayPort;
  GatewayConnectionStatus get connectionStatus => _connectionStatus;

  Timer? _pollTimer;
  Timer? _staleCheckTimer;
  RawDatagramSocket? _udpSocket;
  http.Client? _httpClient;

  @visibleForTesting
  set httpClient(http.Client? client) => _httpClient = client;

  List<TableModel> get currentTables {
    final list = _tables.values
        .where((t) {
          if (!isTableOnline(t.id)) return false;
          final cleanNum = _cleanTableNum(t.tableNumber);
          final cleanId = _cleanTableNum(t.id);
          final cleanDevId = _cleanTableNum(t.deviceId);
          final numPart = _extractNumericId(cleanNum) ?? _extractNumericId(cleanId) ?? _extractNumericId(cleanDevId);
          return _verifiedDeviceIds.contains(cleanNum) ||
                 _verifiedDeviceIds.contains(cleanId) ||
                 _verifiedDeviceIds.contains(cleanDevId) ||
                 (numPart != null && _verifiedDeviceIds.contains(numPart));
        })
        .toList();
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

  String cleanTableNum(dynamic rawId) => _cleanTableNum(rawId);

  String? _extractNumericId(String? id) {
    if (id == null) return null;
    final match = RegExp(r'\d+').firstMatch(id);
    return match?.group(0);
  }

  String _cleanTableNum(dynamic rawId) {
    if (rawId == null) return '1';
    final str = rawId.toString().trim();
    final lower = str.toLowerCase();
    String stripped = str;
    if (lower.startsWith('table_')) {
      stripped = str.substring(6);
    } else if (lower.startsWith('table')) {
      stripped = str.substring(5);
    } else if (lower.startsWith('device_')) {
      stripped = str.substring(7);
    } else if (lower.startsWith('device')) {
      stripped = str.substring(6);
    }
    final clean = stripped.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
    return clean.isNotEmpty ? clean : '1';
  }

  bool isTableOnline(String tableId) {
    final cleanNum = _cleanTableNum(tableId);
    final numId = _extractNumericId(cleanNum);
    final tableIdFull = 'table_${numId ?? cleanNum}';

    final table = _tables[tableIdFull] ??
        _tables[tableId] ??
        _tables[cleanNum] ??
        getLiveTable(tableId);
    if (table != null) {
      final lastSeen = _lastSeenTimes[tableIdFull] ??
          _lastSeenTimes[tableId] ??
          _lastSeenTimes[cleanNum];
      if (lastSeen != null && DateTime.now().difference(lastSeen).inSeconds > 30) {
        return false;
      }
      return table.isDeviceOnline;
    }

    final lastSeen = _lastSeenTimes[tableIdFull] ??
        _lastSeenTimes[tableId] ??
        _lastSeenTimes[cleanNum];
    if (lastSeen != null) {
      return DateTime.now().difference(lastSeen).inSeconds <= 30;
    }
    return false;
  }

  TableModel? getLiveTable(String tableId) {
    final cleanNum = _cleanTableNum(tableId);
    final numId = _extractNumericId(cleanNum);
    final tableIdFull = 'table_${numId ?? cleanNum}';
    if (_tables.containsKey(tableIdFull)) return _tables[tableIdFull];
    if (_tables.containsKey(tableId)) return _tables[tableId];
    if (_tables.containsKey(cleanNum)) return _tables[cleanNum];
    if (numId != null && _tables.containsKey('table_$numId')) return _tables['table_$numId'];
    if (numId != null && _tables.containsKey(numId)) return _tables[numId];
    return _tables.values.cast<TableModel?>().firstWhere(
      (t) =>
          t != null &&
          (_cleanTableNum(t.tableNumber) == cleanNum ||
              _cleanTableNum(t.id) == cleanNum ||
              (numId != null && _cleanTableNum(t.tableNumber) == numId) ||
              (numId != null && _cleanTableNum(t.id) == numId) ||
              t.deviceId == 'device_$cleanNum' ||
              (numId != null && t.deviceId == 'device_$numId')),
      orElse: () => null,
    );
  }

  // Alias for backward compatibility
  TableModel? getLiveBleTable(String tableId) => getLiveTable(tableId);

  void _emitTables() {
    _tablesController.add(currentTables);
  }

  void _setConnectionStatus(GatewayConnectionStatus status) {
    if (_connectionStatus != status) {
      _connectionStatus = status;
      _connectionStatusController.add(status);
      debugPrint(
        '[GATEWAY WIFI] Status Changed -> $status (IP: $_gatewayIp:$_gatewayPort)',
      );
    }
  }

  Future<void> initCachedAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedIp = prefs.getString(_prefKeyGatewayIp);
      if (cachedIp != null && cachedIp.isNotEmpty) {
        _gatewayIp = cachedIp;
        debugPrint('[GATEWAY WIFI] Loaded cached Gateway IP: $_gatewayIp');
      }
    } catch (_) {}
    await _loadStoredCredentials();
  }

  Future<void> _saveCachedGatewayIp(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyGatewayIp, ip);
    } catch (_) {}
  }

  void setGatewayAddress(String ip, {int port = 80}) {
    _gatewayIp = ip;
    _gatewayPort = port;
    _saveCachedGatewayIp(ip);
    refreshDevices();
  }

  Future<bool> testAndSetGatewayIp(String ip, {int port = 80}) async {
    final client = _httpClient ?? http.Client();
    final cleanIp = ip.trim();
    if (cleanIp.isEmpty) return false;

    try {
      final url = Uri.parse('http://$cleanIp:$port/api/status');
      final res = await client.get(url).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['gateway'] != null) {
          final staIp = data['sta_ip']?.toString() ?? '';
          final targetIp = (staIp.isNotEmpty && staIp != '0.0.0.0')
              ? staIp
              : cleanIp;
          _gatewayIp = targetIp;
          _gatewayPort = port;
          _saveCachedGatewayIp(targetIp);
          _setConnectionStatus(GatewayConnectionStatus.connected);
          await fetchGatewayDevices();
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> requestPermissionsAndStartScan() async {
    await startScan();
  }

  Future<void> startScan() async {
    _isScanning = true;
    _isScanningController.add(true);
    _httpClient ??= http.Client();

    // 0. Initialize cached IP if not already loaded
    await initCachedAddress();

    // 1. Start UDP Auto-Discovery listener in background
    _startUdpDiscovery();

    // 2. Start Periodic Stale Check (every 3 seconds)
    _staleCheckTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      _checkStaleDevices();
    });

    // 3. Start Polling Wi-Fi Gateway REST API (every 1.5 seconds)
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      fetchGatewayDevices();
    });

    // Immediate initial fetch & probe
    await findReachableGatewayEndpoint();
    await fetchGatewayDevices();

    _isScanning = false;
    _isScanningController.add(false);
  }

  void _startUdpDiscovery() {
    if (kIsWeb) return;
    try {
      RawDatagramSocket.bind(InternetAddress.anyIPv4, udpDiscoveryPort)
          .then((socket) {
            _udpSocket?.close();
            _udpSocket = socket;
            _udpSocket?.broadcastEnabled = true;
            _udpSocket?.listen((RawSocketEvent event) {
              if (event == RawSocketEvent.read) {
                final dg = _udpSocket?.receive();
                if (dg != null) {
                  try {
                    final message = utf8.decode(dg.data);
                    final json = jsonDecode(message);
                    if (json['gateway'] != null) {
                      final staIp = json['sta_ip']?.toString() ?? '';
                      final ip = json['ip']?.toString() ?? '';
                      final targetIp = staIp.isNotEmpty ? staIp : ip;
                      final port = json['port'] != null
                          ? (json['port'] as num).toInt()
                          : 80;

                      if (targetIp.isNotEmpty &&
                          targetIp != _gatewayIp &&
                          targetIp != '0.0.0.0') {
                        debugPrint(
                          '[UDP DISCOVERY] Discovered Gateway on Router at $targetIp:$port (SSID: ${json['ssid']})',
                        );
                        _gatewayIp = targetIp;
                        _gatewayPort = port;
                        _saveCachedGatewayIp(targetIp);
                        refreshDevices();
                      }
                    }
                  } catch (_) {}
                }
              }
            });
          })
          .catchError((err) {
            debugPrint('[UDP DISCOVERY] Bind error: $err');
          });
    } catch (e) {
      debugPrint('[UDP DISCOVERY] Setup error: $e');
    }
  }

  /// Probe candidate endpoints & scan local subnet to automatically find active Gateway
  Future<String?> findReachableGatewayEndpoint({bool scanSubnet = true}) async {
    final client = _httpClient ?? http.Client();
    final candidates = <String>[_gatewayIp, 'tap2notify.local', '192.168.4.1'];

    for (final host in candidates) {
      if (host.isEmpty || host == '0.0.0.0') continue;
      try {
        final url = Uri.parse('http://$host:$_gatewayPort/api/status');
        final res = await client
            .get(url)
            .timeout(const Duration(milliseconds: 1200));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['gateway'] != null) {
            final staIp = data['sta_ip']?.toString() ?? '';
            final targetIp = (staIp.isNotEmpty && staIp != '0.0.0.0')
                ? staIp
                : host;
            _gatewayIp = targetIp;
            _saveCachedGatewayIp(targetIp);
            _setConnectionStatus(GatewayConnectionStatus.connected);
            debugPrint('[GATEWAY WIFI] Verified active Gateway at $targetIp');
            return targetIp;
          }
        }
      } catch (_) {}
    }

    // If candidate endpoints did not respond, automatically scan the local Wi-Fi subnet
    if (scanSubnet && !kIsWeb) {
      final foundIp = await _scanLocalSubnetForGateway();
      if (foundIp != null) return foundIp;
    }

    return null;
  }

  /// Extracts the local IPv4 subnet prefix (e.g. '192.168.1.') of the phone's active Wi-Fi interface
  Future<String?> _getLocalSubnetPrefix() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            final parts = ip.split('.');
            if (parts.length == 4) {
              return '${parts[0]}.${parts[1]}.${parts[2]}.';
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fast parallel scan of the local router subnet (1..254) to find the Gateway with zero IP entry
  Future<String?> _scanLocalSubnetForGateway() async {
    final prefix = await _getLocalSubnetPrefix();
    if (prefix == null) return null;

    final client = _httpClient ?? http.Client();
    debugPrint(
      '[GATEWAY WIFI] Auto-scanning local subnet ${prefix}1-254 for Gateway...',
    );

    final ipSuffixes = List<int>.generate(254, (i) => i + 1);

    // Concurrent batches of 30 requests with short 650ms timeout for ultra-fast discovery
    for (int i = 0; i < ipSuffixes.length; i += 30) {
      final end = (i + 30 < ipSuffixes.length) ? i + 30 : ipSuffixes.length;
      final chunk = ipSuffixes.sublist(i, end);

      final futures = chunk.map((suffix) async {
        final host = '$prefix$suffix';
        try {
          final url = Uri.parse('http://$host:$_gatewayPort/api/status');
          final res = await client
              .get(url)
              .timeout(const Duration(milliseconds: 650));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data['gateway'] != null) {
              return host;
            }
          }
        } catch (_) {}
        return null;
      });

      final results = await Future.wait(futures);
      final found = results.firstWhere((r) => r != null, orElse: () => null);
      if (found != null) {
        debugPrint(
          '[GATEWAY WIFI] Auto-discovered Gateway on local router at $found',
        );
        _gatewayIp = found;
        _saveCachedGatewayIp(found);
        _setConnectionStatus(GatewayConnectionStatus.connected);
        return found;
      }
    }
    return null;
  }

  // Fetch all active table devices from ESP32-WROOM Wi-Fi Gateway
  Future<void> fetchGatewayDevices() async {
    final client = _httpClient ?? http.Client();
    final url = Uri.parse('http://$_gatewayIp:$_gatewayPort/api/devices');

    try {
      final response = await client
          .get(url)
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        _setConnectionStatus(GatewayConnectionStatus.connected);
        final dynamic body = jsonDecode(response.body);

        if (body is List) {
          for (final item in body) {
            if (item is Map) {
              processDevicePayload(item);
            }
          }
        }
      }
    } catch (e) {
      // If primary IP fails, probe candidate endpoints
      final newIp = await findReachableGatewayEndpoint();
      if (newIp == null &&
          _connectionStatus == GatewayConnectionStatus.connected) {
        _setConnectionStatus(GatewayConnectionStatus.disconnected);
      }
    }
  }

  void processDevicePayload(Map<dynamic, dynamic> device) {
    final rawId =
        device['id']?.toString() ?? device['tableNumber']?.toString() ?? '1';
    final cleanTableNum = _cleanTableNum(rawId);
    final numId = _extractNumericId(cleanTableNum);
    final tableId = 'table_${numId ?? cleanTableNum}';

    // -------------------------------------------------------------
    // DEVICE OWNERSHIP VERIFICATION CHECK (Admission Control)
    // -------------------------------------------------------------
    // Each device has a registered Device ID and Password. A device
    // must be considered valid and shown in the app ONLY when both
    // the Device ID and Password match the stored credentials.
    // If either the ID or Password is incorrect, the device must be
    // treated as unauthorized, must not be connected, and must not
    // appear as an active/available device in the app.
    // Ensure this verification happens before any device registration,
    // connection, assignment, or communication process.
    // -------------------------------------------------------------
    final isVerified = _verifiedDeviceIds.contains(cleanTableNum) ||
        (numId != null && _verifiedDeviceIds.contains(numId));

    if (!isVerified) {
      if (_unauthorizedDeviceIds.contains(cleanTableNum) ||
          (numId != null && _unauthorizedDeviceIds.contains(numId))) {
        return;
      }

      final storedPassword = _storedCredentials[cleanTableNum] ??
          (numId != null ? _storedCredentials[numId] : null);

      if (storedPassword == null) {
        _unauthorizedDeviceIds.add(cleanTableNum);
        if (numId != null) _unauthorizedDeviceIds.add(numId);
        debugPrint(
          '[DEVICE OWNERSHIP] Device $cleanTableNum is not in registered system credentials. Rejected as unauthorized.',
        );
        return;
      }

      // Automatically verify against physical device in background using stored credentials
      final verifyKey = numId ?? cleanTableNum;
      if (!_verifyingDeviceIds.contains(verifyKey)) {
        _verifyingDeviceIds.add(verifyKey);
        verifyDeviceOwnership(
          deviceId: verifyKey,
          password: storedPassword,
        ).then((verified) {
          _verifyingDeviceIds.remove(verifyKey);
          if (verified) {
            processDevicePayload(device);
          }
        }).catchError((_) {
          _verifyingDeviceIds.remove(verifyKey);
        });
      }

      // While unverified, suppress from active/available devices in the app
      return;
    }

    int rawFlag = -1;
    if (device['flag'] != null) {
      if (device['flag'] is num) {
        rawFlag = (device['flag'] as num).toInt();
      } else {
        final fStr = device['flag'].toString().trim().toLowerCase();
        if (fStr == '0' || fStr == 'pending' || fStr == 'new_request' || fStr == 'calling') {
          rawFlag = 0;
        } else if (fStr == '1' || fStr == 'accepted' || fStr == 'in_progress' || fStr == 'serving') {
          rawFlag = 1;
        } else if (fStr == '-2' || fStr == 'locked') {
          rawFlag = -2;
        } else {
          rawFlag = -1;
        }
      }
    } else if (device['status'] != null) {
      final sStr = device['status'].toString().trim().toLowerCase();
      if (sStr == 'pending' || sStr == 'new_request' || sStr == 'calling') {
        rawFlag = 0;
      } else if (sStr == 'accepted' || sStr == 'in_progress' || sStr == 'serving') {
        rawFlag = 1;
      } else if (sStr == 'locked') {
        rawFlag = -2;
      } else {
        rawFlag = -1;
      }
    }

    bool? parseExplicitBool(dynamic val) {
      if (val == null) return null;
      if (val is bool) return val;
      if (val is num) return val == 1;
      final s = val.toString().trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
      return null;
    }

    bool parseBool(dynamic val) => parseExplicitBool(val) ?? false;

    final bool isOnline = parseBool(device['online']) ||
        parseBool(device['isOnline']) ||
        parseBool(device['device_online']) ||
        parseBool(device['deviceOnline']) ||
        parseBool(device['is_online']);

    final bool? explicitUnlocked = parseExplicitBool(device['unlocked']) ??
        parseExplicitBool(device['isUnlocked']) ??
        parseExplicitBool(device['is_unlocked']);

    final bool isHardwareLocked = (rawFlag == -2);
    final bool isExplicitlyLocked = (explicitUnlocked == false) || isHardwareLocked;

    if (isExplicitlyLocked) {
      _unlockedTableIds.remove(tableId);
    } else if (explicitUnlocked == true) {
      _unlockedTableIds.add(tableId);
    }

    final existing = _tables[tableId];
    final bool isUnlocked = !isExplicitlyLocked &&
        (explicitUnlocked == true ||
            _unlockedTableIds.contains(tableId) ||
            (existing?.isUnlocked ?? false));

    final finalFlag = isHardwareLocked ? -1 : rawFlag;
    final finalStatus = isHardwareLocked
        ? 'idle'
        : (rawFlag == 0 ? 'pending' : (rawFlag == 1 ? 'accepted' : 'idle'));

    final int now = DateTime.now().millisecondsSinceEpoch;

    if (isOnline) {
      _lastSeenTimes[tableId] = DateTime.now();
    } else {
      _lastSeenTimes.remove(tableId);
    }

    final bool stateChanged =
        existing == null ||
        existing.flag != finalFlag ||
        existing.status != finalStatus ||
        existing.isUnlocked != isUnlocked ||
        existing.isDeviceOnline != isOnline;

    final dynamic parsedNum = int.tryParse(numId ?? cleanTableNum) ?? int.tryParse(cleanTableNum) ?? cleanTableNum;

    final String assignedWaiterId =
        (existing?.assignedWaiterId.isNotEmpty ?? false)
        ? existing!.assignedWaiterId
        : (device['assigned_waiter_id']?.toString() ??
              device['assignedWaiterId']?.toString() ??
              '');
    final String waiterName = (existing?.waiterName.isNotEmpty ?? false)
        ? existing!.waiterName
        : (device['waiterName']?.toString() ??
              (assignedWaiterId.isNotEmpty ? assignedWaiterId : ''));

    final int? reqSentAt = finalFlag == 0
        ? (existing?.flag == 0 && existing?.requestSentAt != null
            ? existing!.requestSentAt
            : (device['requestSentAt'] != null
                ? (device['requestSentAt'] as num).toInt()
                : (device['request_sent_at'] != null
                    ? (device['request_sent_at'] as num).toInt()
                    : now)))
        : (finalFlag == 1 ? (existing?.requestSentAt ?? device['requestSentAt'] as int?) : null);

    final int? accAt = finalFlag == 1
        ? (existing?.acceptedAt ?? (device['acceptedAt'] as num?)?.toInt() ?? now)
        : null;

    final updatedTable = TableModel(
      id: tableId,
      tableNumber: parsedNum,
      deviceId: 'device_$cleanTableNum',
      status: finalStatus,
      flag: finalFlag,
      waiterName: waiterName,
      assignedWaiterId: assignedWaiterId,
      managerPhone: existing?.managerPhone ?? '',
      managerUid: existing?.managerUid ?? '',
      managerEmail: existing?.managerEmail,
      isDeviceOnline: isOnline,
      isUnlocked: isUnlocked,
      unlockedAt: isUnlocked
          ? (existing?.unlockedAt ?? now)
          : null,
      unlockedBy: existing?.unlockedBy,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      acceptedAt: accAt,
      requestSentAt: reqSentAt,
    );

    _tables[tableId] = updatedTable;

    if (stateChanged) {
      _emitTables();
      debugPrint(
        '[WIFI INSTANT] Table $cleanTableNum STATE CHANGED -> Flag: $finalFlag ($finalStatus, Online: $isOnline, Unlocked: $isUnlocked)',
      );

      if (finalFlag == 0 && isUnlocked) {
        try {
          HapticFeedback.heavyImpact();
        } catch (_) {}
      }

      onDeviceDiscovered?.call(updatedTable);
    }
  }

  @visibleForTesting
  void processDevicePayloadForTesting(
    Map<dynamic, dynamic> device, {
    bool markVerified = true,
  }) {
    if (markVerified) {
      final rawId =
          device['id']?.toString() ?? device['tableNumber']?.toString() ?? '1';
      final clean = _cleanTableNum(rawId);
      final numPart = _extractNumericId(clean);
      _verifiedDeviceIds.add(clean);
      if (numPart != null) _verifiedDeviceIds.add(numPart);
      _unauthorizedDeviceIds.remove(clean);
      if (numPart != null) _unauthorizedDeviceIds.remove(numPart);
    }
    processDevicePayload(device);
  }

  @visibleForTesting
  void resetForTesting() {
    _tables.clear();
    _lastSeenTimes.clear();
    _unlockedTableIds.clear();
    _verifiedDeviceIds.clear();
    _unauthorizedDeviceIds.clear();
    _verifyingDeviceIds.clear();
    _storedCredentials.clear();
    devicePasswordValidator = null;
    httpClient = null;
    onDeviceDiscovered = null;
    onDeviceLost = null;
  }

  void _checkStaleDevices() {
    final now = DateTime.now();
    bool changed = false;

    _lastSeenTimes.forEach((tableId, lastSeen) {
      if (now.difference(lastSeen).inSeconds > 30) {
        final table = _tables[tableId];
        if (table != null && table.isDeviceOnline) {
          final offlineTable = table.copyWith(isDeviceOnline: false);
          _tables[tableId] = offlineTable;
          changed = true;
          debugPrint('[GATEWAY WIFI] Table $tableId is now OFFLINE (stale >30s)');
          onDeviceDiscovered?.call(offlineTable);
        }
      }
    });

    if (changed) {
      _emitTables();
    }
  }

  // ==========================================
  // --- Wi-Fi Provisioning API Methods ---
  // ==========================================

  /// Scan available 2.4GHz Wi-Fi networks around the Gateway
  Future<List<Map<String, dynamic>>> scanGatewayWifiNetworks() async {
    await findReachableGatewayEndpoint();
    final client = _httpClient ?? http.Client();
    final url = Uri.parse('http://$_gatewayIp:$_gatewayPort/api/wifi/scan');

    try {
      final response = await client
          .get(url)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final dynamic list = jsonDecode(response.body);
        if (list is List) {
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('[GATEWAY WIFI] Scan Wi-Fi error: $e');
    }
    return [];
  }

  /// Configure the Gateway to connect to a Wi-Fi Router
  Future<bool> configureGatewayWifi({
    required String ssid,
    required String password,
  }) async {
    // 1. Probe for reachable IP if current is unresponsive
    await findReachableGatewayEndpoint();

    final client = _httpClient ?? http.Client();
    final url = Uri.parse(
      'http://$_gatewayIp:$_gatewayPort/api/wifi/configure',
    );

    final payload = {'ssid': ssid.trim(), 'password': password.trim()};

    try {
      final response = await client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        debugPrint(
          '[GATEWAY WIFI] Wi-Fi router configured successfully with SSID: $ssid',
        );
        return true;
      }
    } catch (e) {
      debugPrint('[GATEWAY WIFI] Configure Wi-Fi error: $e');
    }
    return false;
  }

  /// Check live Wi-Fi connection status of Gateway to router
  Future<Map<String, dynamic>?> getGatewayWifiStatus() async {
    final client = _httpClient ?? http.Client();
    final url = Uri.parse('http://$_gatewayIp:$_gatewayPort/api/wifi/status');

    try {
      final response = await client
          .get(url)
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final staIp = data['sta_ip']?.toString() ?? '';
        if (staIp.isNotEmpty &&
            staIp != _gatewayIp &&
            staIp != '0.0.0.0' &&
            data['status'] == 'connected') {
          _gatewayIp = staIp;
          _saveCachedGatewayIp(staIp);
          _setConnectionStatus(GatewayConnectionStatus.connected);
        }
        return data;
      }
    } catch (e) {
      // Try probing endpoints
      await findReachableGatewayEndpoint();
    }
    return null;
  }

  /// Reset saved Wi-Fi router credentials on Gateway
  Future<bool> resetGatewayWifi() async {
    await findReachableGatewayEndpoint();
    final client = _httpClient ?? http.Client();
    final url = Uri.parse('http://$_gatewayIp:$_gatewayPort/api/wifi/reset');

    try {
      final response = await client
          .post(url)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        debugPrint('[GATEWAY WIFI] Wi-Fi credentials reset on Gateway');
        return true;
      }
    } catch (e) {
      debugPrint('[GATEWAY WIFI] Reset Wi-Fi error: $e');
    }
    return false;
  }

  // ==========================================
  // --- Device Command Dispatching ---
  // ==========================================

  // Send Command to ESP32-WROOM Wi-Fi Gateway
  Future<bool> sendGatewayCommand({
    required String tableId,
    required String command,
    String? password,
    String? waiterName,
  }) async {
    final cleanTableId = tableId.startsWith('table_')
        ? tableId
        : 'table_$tableId';
    final cleanNum = _cleanTableNum(tableId);
    final numPart = _extractNumericId(cleanNum) ?? _extractNumericId(tableId);
    final tableNum = numPart ?? cleanNum;

    // Admission Control: Operational commands (non-AUTH) require verified device ownership
    final isVerified = _verifiedDeviceIds.contains(cleanNum) ||
        (numPart != null && _verifiedDeviceIds.contains(numPart));
    if (command != 'AUTH' && !isVerified) {
      debugPrint(
        '[DEVICE OWNERSHIP] Blocked command $command to unauthorized/unverified device $cleanNum.',
      );
      return false;
    }

    final client = _httpClient ?? http.Client();
    final url = Uri.parse('http://$_gatewayIp:$_gatewayPort/api/command');

    final payload = {
      'deviceId': (numPart != null && numPart.isNotEmpty) ? numPart : cleanNum,
      'command': command,
      'password': ?password,
      'waiterName': ?waiterName,
    };

    try {
      final response = await client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        try {
          final dynamic data = jsonDecode(response.body);
          if (data is Map) {
            // Explicit error / rejection from Gateway or device
            if (data['success'] == false ||
                data['status'] == 'failed' ||
                data['status'] == 'timeout' ||
                data['result'] == 'AUTH_FAIL' ||
                data['result'] == 'SETPWD_FAIL' ||
                data['unlocked'] == false ||
                data['isUnlocked'] == false) {
              debugPrint(
                '[GATEWAY WIFI] Command $command failed on Table $tableNum: ${data['error'] ?? data['result']}',
              );
              return false;
            }

            // Explicit positive confirmation from Gateway firmware
            if (data['result'] == 'AUTH_OK' ||
                data['unlocked'] == true ||
                data['isUnlocked'] == true) {
              debugPrint(
                '[GATEWAY WIFI] Command $command succeeded on Table $tableNum (unlocked: true)',
              );
              return true;
            }

            // Other non-AUTH commands (e.g. TRIGGER, ACCEPT, RESET) that return success
            if (command != 'AUTH' &&
                (data['success'] == true || data['status'] == 'success')) {
              debugPrint(
                '[GATEWAY WIFI] Command $command succeeded on Table $tableNum',
              );
              return true;
            }

            // Older Gateway firmware returning {"status":"sent"}
            if (command == 'AUTH' && data['status'] == 'sent') {
              return await _pollForAuthConfirmation(tableNum, cleanTableId);
            }
          }
        } catch (_) {}

        // For AUTH command, NEVER default to true without explicit authorization confirmation!
        if (command == 'AUTH') {
          debugPrint(
            '[GATEWAY WIFI] AUTH command on Table $tableNum lacked explicit unlock confirmation. Rejecting.',
          );
          return false;
        }

        debugPrint(
          '[GATEWAY WIFI] Command $command sent successfully to Table $tableNum',
        );
        return true;
      } else {
        debugPrint(
          '[GATEWAY WIFI] Command $command failed with HTTP ${response.statusCode}: ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[GATEWAY WIFI] Send command error: $e');
    }

    return false;
  }

  // Poll Gateway events/devices as fallback for older asynchronous gateway firmware
  Future<bool> _pollForAuthConfirmation(
    String tableNum,
    String cleanTableId,
  ) async {
    final client = _httpClient ?? http.Client();
    final eventsUrl = Uri.parse('http://$_gatewayIp:$_gatewayPort/api/events');
    final devicesUrl =
        Uri.parse('http://$_gatewayIp:$_gatewayPort/api/devices');

    for (int i = 0; i < 4; i++) {
      await Future.delayed(const Duration(milliseconds: 350));
      try {
        final evRes =
            await client.get(eventsUrl).timeout(const Duration(seconds: 1));
        if (evRes.statusCode == 200) {
          final dynamic evData = jsonDecode(evRes.body);
          if (evData is Map &&
              (evData['deviceId']?.toString() == tableNum ||
                  evData['tableNumber']?.toString() == tableNum)) {
            if (evData['status'] == 'failed' ||
                evData['result'] == 'AUTH_FAIL' ||
                evData['isUnlocked'] == false ||
                evData['unlocked'] == false) {
              return false;
            }
            if (evData['status'] == 'success' ||
                evData['result'] == 'AUTH_OK' ||
                evData['isUnlocked'] == true ||
                evData['unlocked'] == true) {
              return true;
            }
          }
        }

        final devRes =
            await client.get(devicesUrl).timeout(const Duration(seconds: 1));
        if (devRes.statusCode == 200) {
          final dynamic devData = jsonDecode(devRes.body);
          if (devData is List) {
            for (final d in devData) {
              if (d is Map &&
                  (d['id']?.toString() == tableNum ||
                      d['tableNumber']?.toString() == tableNum)) {
                // Only return true when device transitioned to unlocked
                if (d['unlocked'] == true && d['flag'] != -2) {
                  return true;
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    return false;
  }

  /// Device Ownership Verification: Checks Device ID and Password against device hardware and stored credentials.
  /// If either ID or Password is incorrect, device is treated as unauthorized and cannot connect or appear in the app.
  Future<bool> verifyDeviceOwnership({
    required String deviceId,
    required String password,
  }) async {
    final cleanId = _cleanTableNum(deviceId);
    final numId = _extractNumericId(cleanId);
    final cleanTableId = 'table_${numId ?? cleanId}';
    final trimmedPassword = password.trim();
    if (trimmedPassword.isEmpty) return false;

    // 0. Custom device password validator callback (for unit tests / custom authenticators)
    if (devicePasswordValidator != null) {
      final isValid = await devicePasswordValidator!(
        cleanTableId,
        trimmedPassword,
      );
      if (isValid) {
        _storedCredentials[cleanId] = trimmedPassword;
        if (numId != null) _storedCredentials[numId] = trimmedPassword;
        _verifiedDeviceIds.add(cleanId);
        if (numId != null) _verifiedDeviceIds.add(numId);
        _unauthorizedDeviceIds.remove(cleanId);
        if (numId != null) _unauthorizedDeviceIds.remove(numId);
        _unlockedTableIds.add(cleanTableId);
        _updateTableUnlockState(cleanTableId, true);
        return true;
      }
      _verifiedDeviceIds.remove(cleanId);
      if (numId != null) _verifiedDeviceIds.remove(numId);
      _unauthorizedDeviceIds.add(cleanId);
      if (numId != null) _unauthorizedDeviceIds.add(numId);
      _unlockedTableIds.remove(cleanTableId);
      _updateTableUnlockState(cleanTableId, false);
      _tables.remove(cleanTableId);
      _emitTables();
      return false;
    }

    // Check against stored credentials:
    // If device ID is registered in system credentials, check if password matches
    final expected = _storedCredentials[cleanId] ??
        (numId != null ? _storedCredentials[numId] : null);

    if (expected != null && expected.isNotEmpty && expected != trimmedPassword) {
      // In offline/unit-test mode without reachable hardware:
      if (_connectionStatus != GatewayConnectionStatus.connected && _httpClient == null) {
        _verifiedDeviceIds.remove(cleanId);
        if (numId != null) _verifiedDeviceIds.remove(numId);
        _unauthorizedDeviceIds.add(cleanId);
        if (numId != null) _unauthorizedDeviceIds.add(numId);
        _unlockedTableIds.remove(cleanTableId);
        _updateTableUnlockState(cleanTableId, false);
        _tables.remove(cleanTableId);
        _emitTables();
        debugPrint(
          '[DEVICE OWNERSHIP] Device $cleanId password does not match stored credentials. Verification failed.',
        );
        return false;
      }
    }

    // 1. Send HTTP REST AUTH Command to Wi-Fi Gateway
    final targetDev = numId ?? cleanId;
    final success = await sendGatewayCommand(
      tableId: targetDev,
      command: 'AUTH',
      password: trimmedPassword,
    );

    if (success) {
      _storedCredentials[cleanId] = trimmedPassword;
      if (numId != null) _storedCredentials[numId] = trimmedPassword;
      _verifiedDeviceIds.add(cleanId);
      if (numId != null) _verifiedDeviceIds.add(numId);
      _unauthorizedDeviceIds.remove(cleanId);
      if (numId != null) _unauthorizedDeviceIds.remove(numId);
      _unlockedTableIds.add(cleanTableId);
      _updateTableUnlockState(cleanTableId, true);
      fetchGatewayDevices();
      debugPrint(
        '[DEVICE OWNERSHIP] Device $cleanId ownership successfully VERIFIED.',
      );
      return true;
    } else {
      _verifiedDeviceIds.remove(cleanId);
      if (numId != null) _verifiedDeviceIds.remove(numId);
      _unauthorizedDeviceIds.add(cleanId);
      if (numId != null) _unauthorizedDeviceIds.add(numId);
      _unlockedTableIds.remove(cleanTableId);
      _updateTableUnlockState(cleanTableId, false);
      _tables.remove(cleanTableId);
      _emitTables();
      debugPrint(
        '[DEVICE OWNERSHIP] Device $cleanId ownership verification FAILED. Device treated as unauthorized.',
      );
      return false;
    }
  }

  // Authorize / Unlock Table via Wi-Fi Gateway (delegates to verifyDeviceOwnership)
  Future<bool> verifyDevicePassword({
    required String tableId,
    required String password,
  }) async {
    return verifyDeviceOwnership(
      deviceId: _cleanTableNum(tableId),
      password: password,
    );
  }

  Future<void> revokeDeviceOwnership(String deviceId) async {
    final cleanId = _cleanTableNum(deviceId);
    final numId = _extractNumericId(cleanId);
    final cleanTableId = 'table_${numId ?? cleanId}';
    _verifiedDeviceIds.remove(cleanId);
    if (numId != null) _verifiedDeviceIds.remove(numId);
    _unauthorizedDeviceIds.add(cleanId);
    if (numId != null) _unauthorizedDeviceIds.add(numId);
    _unlockedTableIds.remove(cleanTableId);
    _tables.remove(cleanTableId);
    _emitTables();
    await sendGatewayCommand(tableId: numId ?? cleanId, command: 'LOCK');
  }

  void _updateTableUnlockState(String tableId, bool unlocked) {
    final cleanTableId = tableId.startsWith('table_')
        ? tableId
        : 'table_$tableId';
    final current = _tables[cleanTableId];
    if (current != null) {
      final updated = current.copyWith(
        isUnlocked: unlocked,
        unlockedAt: unlocked ? DateTime.now().millisecondsSinceEpoch : null,
      );
      _tables[cleanTableId] = updated;
      _emitTables();
      onDeviceDiscovered?.call(updated);
    }
  }

  bool isTableUnlocked(String tableId) {
    final cleanId = tableId.startsWith('table_') ? tableId : 'table_$tableId';
    return _unlockedTableIds.contains(cleanId) ||
        (_tables[cleanId]?.isUnlocked ?? false);
  }

  Future<void> unlockTableLocally(String tableId) async {
    final cleanTableId = tableId.startsWith('table_')
        ? tableId
        : 'table_$tableId';
    _unlockedTableIds.add(cleanTableId);
    _updateTableUnlockState(cleanTableId, true);
  }

  Future<void> lockTableLocally(String tableId) async {
    final cleanTableId = tableId.startsWith('table_')
        ? tableId
        : 'table_$tableId';
    _unlockedTableIds.remove(cleanTableId);

    // Send HTTP LOCK Command to Gateway
    await sendGatewayCommand(tableId: tableId, command: 'LOCK');
    _updateTableUnlockState(cleanTableId, false);
  }

  void assignWaiterLocally(String tableId, String waiterId, String waiterName) {
    final cleanTableId = tableId.startsWith('table_')
        ? tableId
        : 'table_$tableId';
    final stripped = cleanTableId.replaceFirst('table_', '');
    final tableNum = int.tryParse(stripped) ?? stripped;
    final existing = _tables[cleanTableId];
    if (existing != null) {
      final bool alreadyAssigned =
          existing.assignedWaiterId == waiterId &&
          existing.waiterName == waiterName &&
          (waiterId.isEmpty ||
              (existing.isUnlocked &&
                  _unlockedTableIds.contains(cleanTableId)));
      if (alreadyAssigned) {
        return;
      }
      final updated = existing.copyWith(
        assignedWaiterId: waiterId,
        waiterName: waiterName,
        isUnlocked: waiterId.isNotEmpty ? true : existing.isUnlocked,
        unlockedAt: waiterId.isNotEmpty
            ? (existing.unlockedAt ?? DateTime.now().millisecondsSinceEpoch)
            : existing.unlockedAt,
      );
      if (waiterId.isNotEmpty) {
        _unlockedTableIds.add(cleanTableId);
      }
      _tables[cleanTableId] = updated;
      _emitTables();
      onDeviceDiscovered?.call(updated);
    } else if (waiterId.isNotEmpty) {
      _unlockedTableIds.add(cleanTableId);
      final newTable = TableModel(
        id: cleanTableId,
        tableNumber: tableNum,
        deviceId: 'device_$stripped',
        assignedWaiterId: waiterId,
        waiterName: waiterName,
        isUnlocked: true,
        unlockedAt: DateTime.now().millisecondsSinceEpoch,
        status: 'idle',
        flag: -1,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      _tables[cleanTableId] = newTable;
      _emitTables();
      onDeviceDiscovered?.call(newTable);
    }
  }

  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? managerUid,
  }) async {
    final cleanNum = _cleanTableNum(tableId);
    final fullTableId = 'table_$cleanNum';
    final parsedNum = int.tryParse(cleanNum) ?? cleanNum;
    final current = _tables[fullTableId] ??
        _tables[tableId] ??
        _tables[cleanNum] ??
        getLiveTable(tableId);
    final int now = DateTime.now().millisecondsSinceEpoch;

    final updated = (current ??
            TableModel(
              id: fullTableId,
              tableNumber: parsedNum,
              deviceId: 'device_$cleanNum',
              createdAt: now,
            ))
        .copyWith(
      flag: 1,
      status: 'accepted',
      waiterName: waiterName,
      acceptedAt: now,
      updatedAt: now,
    );
    _tables[fullTableId] = updated;
    _emitTables();
    onDeviceDiscovered?.call(updated);

    // Forward ACCEPT to Gateway
    await sendGatewayCommand(
      tableId: tableId,
      command: 'ACCEPT',
      waiterName: waiterName,
    );
  }

  Future<void> resetTableStatus(String tableId) async {
    final cleanNum = _cleanTableNum(tableId);
    final fullTableId = 'table_$cleanNum';
    final parsedNum = int.tryParse(cleanNum) ?? cleanNum;
    final current = _tables[fullTableId] ??
        _tables[tableId] ??
        _tables[cleanNum] ??
        getLiveTable(tableId);
    final int now = DateTime.now().millisecondsSinceEpoch;

    final updated = (current ??
            TableModel(
              id: fullTableId,
              tableNumber: parsedNum,
              deviceId: 'device_$cleanNum',
              createdAt: now,
            ))
        .copyWith(
      flag: -1,
      status: 'idle',
      waiterName: '',
      acceptedAt: null,
      requestSentAt: null,
      updatedAt: now,
    );
    _tables[fullTableId] = updated;
    _emitTables();
    onDeviceDiscovered?.call(updated);

    // Forward RESET to Gateway
    await sendGatewayCommand(tableId: tableId, command: 'RESET');
  }

  Future<void> resetAllTables() async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final updatedMap = <String, TableModel>{};
    _tables.forEach((key, table) {
      final updated = table.copyWith(
        flag: -1,
        status: 'idle',
        waiterName: '',
        acceptedAt: null,
        requestSentAt: null,
        updatedAt: now,
      );
      updatedMap[key] = updated;
      onDeviceDiscovered?.call(updated);
    });
    _tables.clear();
    _tables.addAll(updatedMap);
    _emitTables();

    // Forward RESET ALL to Gateway
    await sendGatewayCommand(tableId: 'ALL', command: 'RESET');
  }

  Future<void> triggerTableRequest(
    String tableId, {
    dynamic tableNumber,
  }) async {
    final cleanNum = _cleanTableNum(tableId);
    final fullTableId = 'table_$cleanNum';
    final current = _tables[fullTableId] ??
        _tables[tableId] ??
        _tables[cleanNum] ??
        getLiveTable(tableId);
    final num = tableNumber ??
        (current?.tableNumber ?? int.tryParse(cleanNum) ?? cleanNum);
    final now = DateTime.now().millisecondsSinceEpoch;

    final updated = TableModel(
      id: fullTableId,
      tableNumber: num,
      deviceId: 'device_$cleanNum',
      status: 'pending',
      flag: 0,
      waiterName: current?.waiterName ?? '',
      assignedWaiterId: current?.assignedWaiterId ?? '',
      isDeviceOnline: true,
      isUnlocked: current?.isUnlocked ?? _unlockedTableIds.contains(fullTableId),
      unlockedAt: current?.unlockedAt,
      unlockedBy: current?.unlockedBy,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
      requestSentAt: now,
    );
    _tables[fullTableId] = updated;
    _emitTables();
    onDeviceDiscovered?.call(updated);

    // Forward TRIGGER to Gateway
    await sendGatewayCommand(tableId: tableId, command: 'TRIGGER');
  }

  /// Syncs an incoming table state from Firebase Realtime Database into local Gateway cache
  void syncTableFromCloud(TableModel cloudTable) {
    final cleanNum = _cleanTableNum(cloudTable.tableNumber ?? cloudTable.id);
    final tableId = 'table_$cleanNum';
    final existing = _tables[tableId];

    final int cloudUpdated = cloudTable.updatedAt ?? cloudTable.createdAt;
    final int localUpdated = existing?.updatedAt ?? existing?.createdAt ?? 0;

    if (existing == null || cloudUpdated >= localUpdated) {
      _tables[tableId] = (existing ?? cloudTable).copyWith(
        flag: cloudTable.flag,
        status: cloudTable.status,
        waiterName: cloudTable.waiterName.isNotEmpty ? cloudTable.waiterName : (existing?.waiterName ?? ''),
        assignedWaiterId: cloudTable.assignedWaiterId.isNotEmpty ? cloudTable.assignedWaiterId : (existing?.assignedWaiterId ?? ''),
        isUnlocked: cloudTable.isUnlocked,
        updatedAt: cloudUpdated,
        acceptedAt: cloudTable.acceptedAt ?? existing?.acceptedAt,
        requestSentAt: cloudTable.requestSentAt ?? existing?.requestSentAt,
      );
    }
  }

  Future<void> refreshDevices() async {
    await fetchGatewayDevices();
  }

  void dispose() {
    _pollTimer?.cancel();
    _staleCheckTimer?.cancel();
    _udpSocket?.close();
    _httpClient?.close();
    _tablesController.close();
    _isScanningController.close();
    _connectionStatusController.close();
  }
}
