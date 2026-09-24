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
    final tableIdFull = 'table_$cleanNum';

    final table = _tables[tableIdFull] ??
        _tables[tableId] ??
        _tables[cleanNum] ??
        getLiveTable(tableId);
    if (table != null) {
      return table.isDeviceOnline;
    }

    final lastSeen = _lastSeenTimes[tableIdFull] ??
        _lastSeenTimes[tableId] ??
        _lastSeenTimes[cleanNum];
    if (lastSeen != null) {
      return DateTime.now().difference(lastSeen).inSeconds <= 15;
    }
    return false;
  }

  TableModel? getLiveTable(String tableId) {
    final cleanNum = _cleanTableNum(tableId);
    final tableIdFull = 'table_$cleanNum';
    if (_tables.containsKey(tableIdFull)) return _tables[tableIdFull];
    if (_tables.containsKey(tableId)) return _tables[tableId];
    if (_tables.containsKey(cleanNum)) return _tables[cleanNum];
    return _tables.values.cast<TableModel?>().firstWhere(
      (t) =>
          t != null &&
          (_cleanTableNum(t.tableNumber) == cleanNum ||
              _cleanTableNum(t.id) == cleanNum ||
              t.deviceId == 'device_$cleanNum'),
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
    final tableId = 'table_$cleanTableNum';

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

    final bool isOnline =
        device['online'] == true || device['isOnline'] == true;
    final bool isHardwareLocked = (rawFlag == -2);

    if (isHardwareLocked) {
      _unlockedTableIds.remove(tableId);
    } else if (device['unlocked'] == true) {
      _unlockedTableIds.add(tableId);
    }

    final existing = _tables[tableId];
    final bool hasAssignedWaiter =
        (existing?.assignedWaiterId.isNotEmpty ?? false) ||
        (device['assigned_waiter_id']?.toString().isNotEmpty ?? false);
    final bool isUnlocked =
        !isHardwareLocked &&
        ((existing?.isUnlocked ?? false) ||
            _unlockedTableIds.contains(tableId) ||
            device['unlocked'] == true ||
            hasAssignedWaiter);

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

    final dynamic parsedNum = int.tryParse(cleanTableNum) ?? cleanTableNum;

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
  void processDevicePayloadForTesting(Map<dynamic, dynamic> device) =>
      processDevicePayload(device);

  @visibleForTesting
  void resetForTesting() {
    _tables.clear();
    _lastSeenTimes.clear();
    _unlockedTableIds.clear();
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
          _tables[tableId] = table.copyWith(isDeviceOnline: false);
          changed = true;
          debugPrint('[GATEWAY WIFI] Table $tableId is now OFFLINE (stale >30s)');
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
    final tableNum = tableId.replaceAll(RegExp(r'[^0-9]'), '');
    final client = _httpClient ?? http.Client();
    final url = Uri.parse('http://$_gatewayIp:$_gatewayPort/api/command');

    final payload = {
      'deviceId': tableNum.isNotEmpty ? tableNum : cleanTableId,
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
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        debugPrint(
          '[GATEWAY WIFI] Command $command sent successfully to Table $tableNum',
        );
        return true;
      }
    } catch (e) {
      debugPrint('[GATEWAY WIFI] Send command error: $e');
    }

    return false;
  }

  // Authorize / Unlock Table via Wi-Fi Gateway
  Future<bool> verifyDevicePassword({
    required String tableId,
    required String password,
  }) async {
    final cleanTableId = tableId.startsWith('table_')
        ? tableId
        : 'table_$tableId';
    final trimmedPassword = password.trim();
    if (trimmedPassword.isEmpty) return false;

    // 0. Custom device password validator callback (for unit tests / custom authenticators)
    if (devicePasswordValidator != null) {
      final isValid = await devicePasswordValidator!(
        cleanTableId,
        trimmedPassword,
      );
      if (isValid) {
        _unlockedTableIds.add(cleanTableId);
        _updateTableUnlockState(cleanTableId, true);
        return true;
      }
      return false;
    }

    // 1. Send HTTP REST AUTH Command to Wi-Fi Gateway
    final success = await sendGatewayCommand(
      tableId: tableId,
      command: 'AUTH',
      password: trimmedPassword,
    );

    if (success) {
      _unlockedTableIds.add(cleanTableId);
      _updateTableUnlockState(cleanTableId, true);
      return true;
    }

    return false;
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
        isUnlocked: cloudTable.isUnlocked || (existing?.isUnlocked ?? false),
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
