import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/gateway_wifi_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_bottom_navbar.dart';
import '../../service_requests/domain/table_model.dart';
import '../../service_requests/presentation/service_request_providers.dart';
import '../../overview/view/overview_tab_view.dart';
import '../../setting/view/settings_tab_view.dart';
import 'views/tables_tab_view.dart';
import 'widgets/table_setup_dialog.dart';
import 'widgets/assign_waiter_modal.dart';
import 'widgets/waiter_management_sheet.dart';
import 'widgets/wifi_gateway_setup_dialog.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentTabIndex = 0; // 0 = Tables, 1 = Overview, 2 = Settings
  String _selectedFilter =
      'all'; // 'all', 'pending', 'accepted', 'idle', 'assigned', 'unassigned'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gatewayWifiServiceProvider).startScan();
    });
  }

  void _showGatewayInfoModal(
    List<TableModel> tables,
    bool isScanning,
    GatewayConnectionStatus connectionStatus,
    String gatewayIp,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isConnected = connectionStatus == GatewayConnectionStatus.connected;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: (isConnected
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF0284C7))
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isConnected
                              ? Icons.wifi_rounded
                              : Icons.wifi_find_rounded,
                          color: isConnected
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF0284C7),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wi-Fi Gateway Telemetry',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5,
                            ),
                          ),
                          Text(
                            isConnected
                                ? 'Hardware bridge active & synced'
                                : 'Scanning local network for ESP32',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Devices',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ref.read(gatewayWifiServiceProvider).refreshDevices();
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
              const Divider(height: 24),
              _buildDiagRow(
                'Gateway Status',
                isConnected ? 'Connected ✓ (Online)' : 'Searching Gateway...',
                isConnected ? const Color(0xFF22C55E) : const Color(0xFFF57C00),
              ),
              _buildDiagRow(
                'Gateway IP Address',
                gatewayIp.isNotEmpty ? '$gatewayIp:80' : 'Auto-detecting',
                isDark ? Colors.white70 : const Color(0xFF334155),
              ),
              _buildDiagRow(
                'Communication Mode',
                'Pure Wi-Fi (REST / Event Stream)',
                const Color(0xFF0284C7),
              ),
              _buildDiagRow(
                'Registered Tables',
                '${tables.length} Total Devices',
                isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              const SizedBox(height: 12),
              Text(
                'ESP32-WROOM Gateway communicates over local Wi-Fi with instant sub-5ms event dispatching to staff terminals.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(ctx);
                    WifiGatewaySetupDialog.show(
                      context,
                      wifiService: ref.read(gatewayWifiServiceProvider),
                    );
                  },
                  icon: const Icon(Icons.router_rounded, size: 18),
                  label: const Text(
                    'CONFIGURE GATEWAY ROUTER',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiagRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: valueColor,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tablesAsync = ref.watch(tablesStreamProvider);
    final wifiService = ref.watch(gatewayWifiServiceProvider);
    final connectionStatus =
        ref.watch(gatewayConnectionStatusStreamProvider).value ??
        wifiService.connectionStatus;
    final isScanning = ref.watch(gatewayScanningStreamProvider).value ?? false;
    final isConnected = connectionStatus == GatewayConnectionStatus.connected;

    final tablesList = tablesAsync.value ?? [];

    final unlockedTables = tablesList.where((t) => t.isUnlocked).toList();
    final lockedTables = tablesList.where((t) => !t.isUnlocked).toList();

    final pendingTables = unlockedTables.where((t) => t.isPending).toList();
    final acceptedTables = unlockedTables.where((t) => t.isAccepted).toList();
    final idleTables = unlockedTables.where((t) => t.isIdle).toList();

    List<TableModel> displayList = [];
    if (_selectedFilter == 'pending') {
      displayList = pendingTables;
    } else if (_selectedFilter == 'accepted') {
      displayList = acceptedTables;
    } else if (_selectedFilter == 'idle') {
      displayList = idleTables;
    } else if (_selectedFilter == 'assigned') {
      displayList = unlockedTables.where((t) => t.isAssigned).toList();
    } else if (_selectedFilter == 'unassigned') {
      displayList = unlockedTables.where((t) => !t.isAssigned).toList();
    } else if (_selectedFilter == 'locked') {
      displayList = lockedTables;
    } else if (_selectedFilter == 'unlocked') {
      displayList = unlockedTables;
    } else {
      displayList = unlockedTables;
    }

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : const Color(0xFFF8FAFC),
      extendBody: true,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? AppColors.darkSurface : Colors.white,
        toolbarHeight: 64,
        title: Row(
          children: [
            // App Brand Logo Container
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryOrange.withValues(
                      alpha: isDark ? 0.2 : 0.12,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Image.asset(
                    isDark
                        ? 'assets/images/app_logo.png'
                        : 'assets/images/app_logo_white.png',
                    key: ValueKey(isDark),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.notifications_active_rounded,
                      color: AppColors.primaryOrange,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // App Name & Admin Badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tab2Notify',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'MANAGER CONSOLE',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: AppColors.primaryOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Wi-Fi Gateway Status Pill
          Padding(
            padding: const EdgeInsets.only(right: 14.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                HapticFeedback.lightImpact();
                _showGatewayInfoModal(
                  tablesList,
                  isScanning,
                  connectionStatus,
                  wifiService.gatewayIp,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (isConnected
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF0284C7))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (isConnected
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF0284C7))
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isConnected
                          ? Icons.wifi_rounded
                          : Icons.wifi_find_rounded,
                      size: 15,
                      color: isConnected
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isConnected ? 'Gateway Online' : 'Searching Wi-Fi',
                      style: TextStyle(
                        color: isConnected
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF0284C7),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          // Tab 0: Tables Grid
          TablesTabView(
            tablesList: tablesList,
            unlockedTables: unlockedTables,
            lockedTables: lockedTables,
            displayList: displayList,
            pendingTables: pendingTables,
            acceptedTables: acceptedTables,
            idleTables: idleTables,
            selectedFilter: _selectedFilter,
            onFilterChanged: (val) => setState(() => _selectedFilter = val),
            onConfigureTables: () =>
                TableSetupDialog.show(context, tablesList.length),
            onManageWaiters: () => WaiterManagementSheet.show(context),
            onAssignWaiters: () =>
                AssignWaiterModal.show(context, allTables: tablesList),
            isScanning: isScanning,
            connectionStatus: connectionStatus,
            onGatewayInfoTap: () => _showGatewayInfoModal(
              tablesList,
              isScanning,
              connectionStatus,
              wifiService.gatewayIp,
            ),
          ),

          // Tab 1: Overview Analytics
          OverviewTabView(
            tables: tablesList,
            onSelectTab: (idx) => setState(() => _currentTabIndex = idx),
          ),

          // Tab 2: Settings & Profile
          const SettingsTabView(),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentTabIndex,
        onTap: (index) => setState(() => _currentTabIndex = index),
        pendingCount: pendingTables.length,
      ),
    );
  }
}
