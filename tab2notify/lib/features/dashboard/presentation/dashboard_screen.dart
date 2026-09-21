import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/gateway_wifi_service.dart';
import '../../../core/widgets/custom_bottom_navbar.dart';
import '../../service_requests/domain/table_model.dart';
import '../../service_requests/presentation/service_request_providers.dart';
import '../../overview/view/overview_tab_view.dart';
import '../../setting/view/settings_tab_view.dart';
import 'views/tables_tab_view.dart';
import 'widgets/table_setup_dialog.dart';
import 'widgets/assign_waiter_modal.dart';
import 'widgets/waiter_management_sheet.dart';

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
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isConnected ? const Color(0xFF2E7D32) : const Color(0xFF0284C7))
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isConnected ? Icons.wifi_rounded : Icons.wifi_find_rounded,
                          color: isConnected ? const Color(0xFF2E7D32) : const Color(0xFF0284C7),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Wi-Fi Gateway Diagnostics',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Devices',
                    onPressed: () {
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
                isConnected ? const Color(0xFF2E7D32) : const Color(0xFFF57C00),
              ),
              _buildDiagRow(
                'Gateway IP Address',
                '$gatewayIp:80',
                isDark ? Colors.white70 : Colors.black87,
              ),
              _buildDiagRow(
                'Communication Mode',
                'Pure Wi-Fi (REST / Event Stream)',
                const Color(0xFF0284C7),
              ),
              _buildDiagRow(
                'Total Devices Found',
                '${tables.length} Tables Registered',
                isDark ? Colors.white : Colors.black87,
              ),
              const SizedBox(height: 12),
              const Text(
                'ESP32-WROOM Gateway communicates over local Wi-Fi with instant sub-5ms event dispatching.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
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
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: valueColor,
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
    final isScanning =
        ref.watch(gatewayScanningStreamProvider).value ?? false;
    final isConnected = connectionStatus == GatewayConnectionStatus.connected;

    final tablesList = tablesAsync.value ?? [];

    final unlockedTables = tablesList.where((t) => t.isUnlocked).toList();
    final lockedTables = tablesList.where((t) => !t.isUnlocked).toList();

    final pendingTables = unlockedTables.where((t) => t.isPending).toList();
    final acceptedTables = unlockedTables.where((t) => t.isAccepted).toList();
    final idleTables = unlockedTables
        .where((t) => !t.isPending && !t.isAccepted)
        .toList();

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
      // Default: 'all' filter shows only unlocked tables
      displayList = unlockedTables;
    }

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(
                      alpha: isDark ? 0.25 : 0.15,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Image.asset(
                    isDark
                        ? 'assets/images/app_logo.png'
                        : 'assets/images/app_logo_white.png',
                    key: ValueKey(isDark),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.notifications_active_rounded,
                      color: theme.colorScheme.primary,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Tab2Notify',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Wi-Fi Gateway Status Pill
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showGatewayInfoModal(
                tablesList,
                isScanning,
                connectionStatus,
                wifiService.gatewayIp,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: (isConnected
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF0284C7))
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isConnected
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF0284C7))
                        .withValues(alpha: 0.4),
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
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isConnected ? 'Gateway Connected' : 'Wi-Fi Searching',
                      style: TextStyle(
                        color: isConnected
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF0284C7),
                        fontWeight: FontWeight.bold,
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
