import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'gateway_wifi_service.dart';
import 'firebase_realtime_service.dart';

class AppConnectivityService {
  static final AppConnectivityService _instance =
      AppConnectivityService._internal();
  factory AppConnectivityService() => _instance;

  AppConnectivityService._internal() {
    _init();
  }

  final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _connectivityController.stream;

  bool _hasConnectivity = true;
  bool get hasConnectivity {
    if (_overrideForTesting != null) {
      return _overrideForTesting!;
    }
    return _hasConnectivity;
  }

  bool _isGatewayConnected = false;
  bool get isGatewayConnected => _isGatewayConnected;

  bool _isCloudConnected = false;
  bool get isCloudConnected => _isCloudConnected;

  Timer? _monitorTimer;
  StreamSubscription? _gatewaySub;
  StreamSubscription? _firebaseSub;

  bool? _overrideForTesting;

  @visibleForTesting
  void setConnectivityForTesting(bool? value) {
    _overrideForTesting = value;
    _updateConnectivity(value ?? _hasConnectivity);
  }

  @visibleForTesting
  void resetForTesting() {
    _overrideForTesting = null;
    _hasConnectivity = true;
    _isGatewayConnected = false;
    _isCloudConnected = false;
  }

  void _init() {
    // 1. Listen to Gateway connection status events
    try {
      final gateway = GatewayWifiService();
      _isGatewayConnected = gateway.isConnected;
      _gatewaySub = gateway.connectionStatusStream.listen((status) {
        final connected = status == GatewayConnectionStatus.connected;
        if (_isGatewayConnected != connected) {
          _isGatewayConnected = connected;
          _reevaluateConnectivity();
        }
      });
    } catch (_) {}

    // 2. Listen to Firebase Realtime Database connection status events
    try {
      final firebase = FirebaseRealtimeService();
      _firebaseSub = firebase.connectionStatusStream.listen((connected) {
        if (_isCloudConnected != connected) {
          _isCloudConnected = connected;
          _reevaluateConnectivity();
        }
      });
    } catch (_) {}

    // 3. Periodic reachability monitor (every 2.5 seconds in production)
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      probeReachability();
    });

    probeReachability();
  }

  Future<void> probeReachability() async {
    if (kIsWeb) return;
    if (_overrideForTesting != null) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final gwConnected = GatewayWifiService().isConnected;
    _isGatewayConnected = gwConnected;
    if (gwConnected) {
      _updateConnectivity(true);
      return;
    }

    bool internetReachable = false;
    try {
      final interfaces = await NetworkInterface.list();
      final hasActiveInterface = interfaces.any((iface) =>
          !iface.name.toLowerCase().contains('loopback') &&
          iface.addresses.any((addr) => !addr.isLoopback));

      if (hasActiveInterface) {
        final lookup = await InternetAddress.lookup('8.8.8.8')
            .timeout(const Duration(milliseconds: 1500));
        internetReachable =
            lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      }
    } catch (_) {
      internetReachable = false;
    }

    _isCloudConnected = internetReachable;
    _reevaluateConnectivity();
  }

  void _reevaluateConnectivity() {
    final bool newStatus = _isGatewayConnected || _isCloudConnected;
    _updateConnectivity(newStatus);
  }

  void _updateConnectivity(bool connected) {
    if (_hasConnectivity != connected) {
      _hasConnectivity = connected;
      debugPrint(
        '[APP CONNECTIVITY] Status Changed -> ${connected ? "ONLINE (Gateway: $_isGatewayConnected, Cloud: $_isCloudConnected)" : "OFFLINE (No Connectivity - All Devices OFFLINE)"}',
      );
      if (!_connectivityController.isClosed) {
        _connectivityController.add(connected);
      }
    }
  }

  void dispose() {
    _monitorTimer?.cancel();
    _gatewaySub?.cancel();
    _firebaseSub?.cancel();
    _connectivityController.close();
  }
}
