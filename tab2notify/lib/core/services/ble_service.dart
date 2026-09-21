// Tab2Notify - Pure Wi-Fi Gateway Service (BLE Removed)
// This file exports GatewayWifiService and provides a drop-in alias for backwards compatibility.

export 'gateway_wifi_service.dart';

import 'gateway_wifi_service.dart';

typedef BleService = GatewayWifiService;
