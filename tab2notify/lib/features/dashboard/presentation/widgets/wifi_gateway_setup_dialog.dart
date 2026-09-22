import 'package:flutter/material.dart';
import '../../../../core/services/gateway_wifi_service.dart';

class WifiGatewaySetupDialog extends StatefulWidget {
  final GatewayWifiService wifiService;

  const WifiGatewaySetupDialog({
    super.key,
    required this.wifiService,
  });

  static Future<void> show(
    BuildContext context, {
    GatewayWifiService? wifiService,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WifiGatewaySetupDialog(
        wifiService: wifiService ?? GatewayWifiService(),
      ),
    );
  }

  @override
  State<WifiGatewaySetupDialog> createState() => _WifiGatewaySetupDialogState();
}

class _WifiGatewaySetupDialogState extends State<WifiGatewaySetupDialog> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();

  bool _obscurePassword = true;
  bool _isScanningNetworks = false;
  bool _isConfiguring = false;
  bool _isTestingIp = false;
  List<Map<String, dynamic>> _scannedNetworks = [];
  Map<String, dynamic>? _wifiStatus;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _ipController.text = widget.wifiService.gatewayIp;
    _fetchCurrentStatus();
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentStatus() async {
    final status = await widget.wifiService.getGatewayWifiStatus();
    if (mounted && status != null) {
      setState(() {
        _wifiStatus = status;
        if (status['ssid'] != null && status['ssid'].toString().isNotEmpty) {
          _ssidController.text = status['ssid'].toString();
        }
        if (status['sta_ip'] != null && status['sta_ip'].toString().isNotEmpty && status['sta_ip'] != '0.0.0.0') {
          _ipController.text = status['sta_ip'].toString();
        }
      });
    }
  }

  Future<void> _testDirectIp() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    setState(() {
      _isTestingIp = true;
      _statusMessage = 'Connecting to Gateway at $ip...';
      _isSuccess = false;
    });

    final success = await widget.wifiService.testAndSetGatewayIp(ip);

    if (mounted) {
      setState(() {
        _isTestingIp = false;
        if (success) {
          _statusMessage = '✓ Connected to Gateway at $ip!';
          _isSuccess = true;
          _fetchCurrentStatus();
        } else {
          _statusMessage = 'Could not reach Gateway at $ip. Check IP address and ensure phone is on same Wi-Fi.';
          _isSuccess = false;
        }
      });
    }
  }

  Future<void> _scanNetworks() async {
    setState(() {
      _isScanningNetworks = true;
      _statusMessage = null;
    });

    final networks = await widget.wifiService.scanGatewayWifiNetworks();

    if (mounted) {
      setState(() {
        _isScanningNetworks = false;
        _scannedNetworks = networks;
        if (networks.isEmpty) {
          _statusMessage = 'No Wi-Fi networks found. If in initial setup, ensure phone is connected to T2N_GATEWAY or same router.';
        }
      });
    }
  }

  Future<void> _saveAndConnect() async {
    final ssid = _ssidController.text.trim();
    final pass = _passController.text.trim();

    if (ssid.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter or select a Wi-Fi Router SSID.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isConfiguring = true;
      _statusMessage = 'Verifying Gateway endpoint & sending Wi-Fi credentials...';
      _isSuccess = false;
    });

    final success = await widget.wifiService.configureGatewayWifi(
      ssid: ssid,
      password: pass,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _statusMessage = 'Credentials sent! Gateway connecting to "$ssid" in STA mode...';
        _isSuccess = true;
      });

      // Poll for 12 seconds to capture new router IP
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) break;
        final status = await widget.wifiService.getGatewayWifiStatus();
        if (status != null && status['status'] == 'connected') {
          setState(() {
            _wifiStatus = status;
            _statusMessage = '✓ Connected to "$ssid"! Router IP: ${status['sta_ip']}';
          });
          break;
        }
      }
    } else {
      setState(() {
        _statusMessage = 'Could not reach Gateway. If configuring for the first time, connect your phone Wi-Fi to "T2N_GATEWAY" hotspot first.';
        _isSuccess = false;
      });
    }

    if (mounted) {
      setState(() {
        _isConfiguring = false;
      });
    }
  }

  Future<void> _resetWifi() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Gateway Wi-Fi?'),
        content: const Text(
          'This will clear saved router credentials from the Gateway. It will start the setup hotspot (T2N_GATEWAY) for re-provisioning.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isConfiguring = true;
      _statusMessage = 'Resetting Wi-Fi credentials on Gateway...';
    });

    final success = await widget.wifiService.resetGatewayWifi();

    if (mounted) {
      setState(() {
        _isConfiguring = false;
        if (success) {
          _statusMessage = 'Wi-Fi reset complete. Gateway fallback hotspot active.';
          _isSuccess = true;
          _wifiStatus = null;
        } else {
          _statusMessage = 'Failed to reset Wi-Fi on Gateway.';
          _isSuccess = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isConnected = widget.wifiService.isConnected;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B26) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.router_rounded, color: Color(0xFF0284C7), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gateway Wi-Fi Router Setup',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Connect Gateway to your Wi-Fi Router (STA Mode)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Info Card: Explaining Architecture
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF0284C7), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gateway connects to your router in pure client (STA) mode. Ensure both your Phone & ESP32-WROOM are connected to the same Wi-Fi router for communication.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Gateway Connection Status Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isConnected ? const Color(0xFF2E7D32) : const Color(0xFFF57C00))
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (isConnected ? const Color(0xFF2E7D32) : const Color(0xFFF57C00))
                      .withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isConnected ? Icons.check_circle_rounded : Icons.wifi_find_rounded,
                    color: isConnected ? const Color(0xFF2E7D32) : const Color(0xFFF57C00),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isConnected
                              ? 'Gateway Connected (${widget.wifiService.gatewayIp})'
                              : 'Gateway Disconnected / Searching...',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isConnected ? const Color(0xFF2E7D32) : const Color(0xFFF57C00),
                          ),
                        ),
                        if (_wifiStatus != null)
                          Text(
                            'SSID: ${_wifiStatus?['ssid'] ?? 'None'} • Mode: ${_wifiStatus?['mode'] ?? 'STA'} • Signal: ${_wifiStatus?['rssi'] ?? 0} dBm',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _fetchCurrentStatus,
                    tooltip: 'Refresh Status',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Wi-Fi Scan Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Wi-Fi Networks (2.4GHz)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _isScanningNetworks ? null : _scanNetworks,
                  icon: _isScanningNetworks
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar_rounded, size: 16),
                  label: Text(_isScanningNetworks ? 'Scanning...' : 'Scan Networks'),
                ),
              ],
            ),

            // Scanned Network Picker
            if (_scannedNetworks.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 130),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _scannedNetworks.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.withValues(alpha: 0.1)),
                  itemBuilder: (context, index) {
                    final net = _scannedNetworks[index];
                    final ssid = net['ssid']?.toString() ?? '';
                    final rssi = net['rssi']?.toString() ?? '';
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.wifi, size: 18),
                      title: Text(ssid, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Signal: $rssi dBm', style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        setState(() {
                          _ssidController.text = ssid;
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // SSID Input
            TextField(
              controller: _ssidController,
              decoration: InputDecoration(
                labelText: 'Wi-Fi Router SSID',
                hintText: 'Enter SSID or tap "Scan Networks"',
                prefixIcon: const Icon(Icons.wifi_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const SizedBox(height: 12),

            // Password Input
            TextField(
              controller: _passController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Wi-Fi Router Password',
                hintText: 'Enter Wi-Fi password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Gateway IP Input & Direct Connect
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      labelText: 'Gateway IP Address',
                      hintText: 'e.g. 192.168.1.15',
                      prefixIcon: const Icon(Icons.settings_ethernet_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isTestingIp ? null : _testDirectIp,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isTestingIp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test IP'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Status message
            if (_statusMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (_isSuccess ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (_isSuccess ? Colors.green : Colors.orange).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSuccess ? Icons.check_circle_outline : Icons.info_outline,
                      color: _isSuccess ? Colors.green : Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _isSuccess ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isConfiguring ? null : _resetWifi,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset Wi-Fi'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isConfiguring ? null : _saveAndConnect,
                    icon: _isConfiguring
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(_isConfiguring ? 'Connecting...' : 'Connect to Router'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
