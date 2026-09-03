import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_provider.dart';
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
  String _selectedFilter = 'all'; // 'all', 'pending', 'accepted', 'idle', 'assigned', 'unassigned'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleServiceProvider).requestPermissionsAndStartScan();
    });
  }

  void _showAcceptDialog(TableModel table) {
    final waiterController = TextEditingController(
      text: table.waiterName.isNotEmpty ? table.waiterName : 'Staff',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.table_restaurant_rounded,
                  color: Color(0xFFE53935),
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Table ${table.tableNumber} Request',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Guest is calling for service 🔴',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: waiterController,
                decoration: InputDecoration(
                  labelText: 'Assigned Waiter / Staff Name',
                  hintText: 'e.g. Rahul Sharma (W001)',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final assignedWaiter = waiterController.text.trim();
                Navigator.pop(dialogContext);

                final repo = ref.read(serviceRequestRepositoryProvider);
                await repo.acceptTableRequest(
                  tableId: table.id,
                  waiterName: assignedWaiter.isNotEmpty ? assignedWaiter : 'Staff',
                );

                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '🟢 Table ${table.tableNumber} Accepted! Waiter: ${assignedWaiter.isNotEmpty ? assignedWaiter : "Staff"}',
                      ),
                      backgroundColor: const Color(0xFF2E7D32),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text(
                'ACCEPT REQUEST',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCompleteDialog(TableModel table) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF2E7D32),
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Table ${table.tableNumber}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                table.waiterName.isNotEmpty
                    ? 'Assigned: ${table.waiterName}'
                    : 'Request is currently ACCEPTED 🟢',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CLOSE', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(dialogContext);

                final repo = ref.read(serviceRequestRepositoryProvider);
                await repo.resetTableStatus(table.id);

                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '✓ Table ${table.tableNumber} marked as Idle/Ready.',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text(
                'MARK AS IDLE',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showBleInfoModal(
    List<TableModel> tables,
    bool isScanning,
    BluetoothAdapterState adapterState,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bluetooth_audio_rounded,
                          color: Color(0xFF0284C7),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'BLE Radar Diagnostics',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Restart Scan',
                    onPressed: () {
                      ref.read(bleServiceProvider).startScan();
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
              const Divider(height: 24),
              _buildDiagRow(
                'Adapter Status',
                adapterState == BluetoothAdapterState.on
                    ? 'Bluetooth ON ✓'
                    : 'Bluetooth OFF ✗',
                adapterState == BluetoothAdapterState.on
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFE53935),
              ),
              _buildDiagRow(
                'Radar Scanner',
                isScanning ? 'Actively Scanning...' : 'Idle',
                isScanning ? const Color(0xFF0284C7) : Colors.grey,
              ),
              _buildDiagRow(
                'Total Devices Found',
                '${tables.length} Tables Registered',
                isDark ? Colors.white : Colors.black87,
              ),
              const SizedBox(height: 12),
              const Text(
                'Pressing your physical ESP32 device button transmits raw BLE manufacturer packets to this app instantly.',
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
    final tablesAsync = ref.watch(tablesStreamProvider);
    final bleScanState = ref.watch(bleScanningStreamProvider).value ?? false;
    final adapterState = ref.watch(bleAdapterStateStreamProvider).value ?? BluetoothAdapterState.unknown;

    final tablesList = tablesAsync.value ?? [];

    final pendingTables = tablesList.where((t) => t.isPending).toList();
    final acceptedTables = tablesList.where((t) => t.isAccepted).toList();
    final idleTables = tablesList
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
      displayList = tablesList.where((t) => t.isAssigned).toList();
    } else if (_selectedFilter == 'unassigned') {
      displayList = tablesList.where((t) => !t.isAssigned).toList();
    } else {
      displayList = tablesList;
    }

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.hotel_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text(
              'Tab2Notify',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // BLE Radar Scanner Pill
          Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showBleInfoModal(
                tablesList,
                bleScanState,
                adapterState,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: (bleScanState
                          ? const Color(0xFF0284C7)
                          : Colors.grey)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (bleScanState
                            ? const Color(0xFF0284C7)
                            : Colors.grey)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      bleScanState
                          ? Icons.bluetooth_searching_rounded
                          : Icons.bluetooth_disabled_rounded,
                      size: 15,
                      color: bleScanState
                          ? const Color(0xFF0284C7)
                          : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      bleScanState ? 'BLE Active' : 'Offline',
                      style: TextStyle(
                        color: bleScanState
                            ? const Color(0xFF0284C7)
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Toggle Theme',
            icon: Icon(
              theme.brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          // Tab 0: Tables Grid
          TablesTabView(
            tablesList: tablesList,
            displayList: displayList,
            pendingTables: pendingTables,
            acceptedTables: acceptedTables,
            idleTables: idleTables,
            selectedFilter: _selectedFilter,
            onFilterChanged: (val) => setState(() => _selectedFilter = val),
            onConfigureTables: () => TableSetupDialog.show(context, tablesList.length),
            onManageWaiters: () => WaiterManagementSheet.show(context),
            onAssignWaiters: () => AssignWaiterModal.show(context, allTables: tablesList),
            onTableTap: (table) {
              if (table.isPending) {
                _showAcceptDialog(table);
              } else if (table.isAccepted) {
                _showCompleteDialog(table);
              } else {
                // Tapping idle table opens quick assign modal for this table
                AssignWaiterModal.show(
                  context,
                  initialTable: table,
                  allTables: tablesList,
                );
              }
            },
            isScanning: bleScanState,
            adapterState: adapterState,
            onBleInfoTap: () => _showBleInfoModal(
              tablesList,
              bleScanState,
              adapterState,
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

