import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/table_card.dart';
import '../../service_requests/domain/table_model.dart';
import '../../service_requests/presentation/service_request_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _selectedFilter = 'all'; // 'all', 'pending', 'accepted', 'idle'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleServiceProvider).requestPermissionsAndStartScan();
    });
  }

  void _showAcceptDialog(TableModel table) {
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
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Customer requested service',
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
              child: const Text(
                'DISMISS',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(dialogContext);

                final repo = ref.read(serviceRequestRepositoryProvider);
                await repo.acceptTableRequest(
                  tableId: table.id,
                  waiterName: 'Staff',
                );

                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '🟢 Table ${table.tableNumber} Request Accepted!',
                      ),
                      backgroundColor: const Color(0xFF2E7D32),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text(
                'ACCEPT',
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
                'Request is currently ACCEPTED 🟢',
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
    final isBtOn = adapterState == BluetoothAdapterState.on;
    final onlineCount = tables.where((t) => t.isDeviceOnline).length;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
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
                      Icon(
                        Icons.bluetooth_rounded,
                        color: isBtOn
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE53935),
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'BLE Network Status',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isBtOn
                          ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
                          : const Color(0xFFE53935).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      isBtOn
                          ? (isScanning ? 'SCANNING' : 'ONLINE')
                          : 'BLUETOOTH OFF',
                      style: TextStyle(
                        color: isBtOn
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE53935),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              _buildDetailRow(
                'Protocol',
                'Bluetooth Low Energy (BLE Advertising & GATT)',
              ),
              _buildDetailRow(
                'Active Connected Tables',
                '$onlineCount of ${tables.length} in range',
              ),
              _buildDetailRow(
                'Service UUID',
                '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
              ),
              _buildDetailRow(
                'Zero Configuration',
                'No Wi-Fi / Router / Internet needed',
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ref.read(bleServiceProvider).startScan();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(
                    'Re-scan Nearby Tables',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
    final isScanningAsync = ref.watch(bleScanningStreamProvider);
    final adapterStateAsync = ref.watch(bleAdapterStateStreamProvider);

    final tablesList = tablesAsync.value ?? [];
    final isScanning = isScanningAsync.value ?? false;
    final adapterState =
        adapterStateAsync.value ?? BluetoothAdapterState.unknown;

    final onlineCount = tablesList.where((t) => t.isDeviceOnline).length;
    final hasOnlineDevices = onlineCount > 0;

    final pendingTables = tablesList.where((t) => t.isPending).toList();
    final acceptedTables = tablesList.where((t) => t.isAccepted).toList();
    final idleTables = tablesList.where((t) => t.isIdle).toList();

    List<TableModel> displayList = [];
    if (_selectedFilter == 'pending') {
      displayList = pendingTables;
    } else if (_selectedFilter == 'accepted') {
      displayList = acceptedTables;
    } else if (_selectedFilter == 'idle') {
      displayList = idleTables;
    } else {
      displayList = tablesList;
    }

    return Scaffold(
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
          // Live BLE Status Badge (Green Dot = Online, Red Dot = Offline)
          Center(
            child: InkWell(
              onTap: () =>
                  _showBleInfoModal(tablesList, isScanning, adapterState),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: hasOnlineDevices
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
                      : const Color(0xFFE53935).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hasOnlineDevices
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFE53935),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: hasOnlineDevices
                            ? const Color(0xFF00E676)
                            : const Color(0xFFE53935),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                (hasOnlineDevices
                                        ? const Color(0xFF00E676)
                                        : const Color(0xFFE53935))
                                    .withValues(alpha: 0.7),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasOnlineDevices ? '$onlineCount Online' : 'No Devices',
                      style: TextStyle(
                        color: hasOnlineDevices
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE53935),
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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Hotel Tables',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Filter Tables',
                        initialValue: _selectedFilter,
                        onSelected: (value) {
                          setState(() => _selectedFilter = value);
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.3,
                              ),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.filter_list_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _selectedFilter == 'all'
                                    ? 'All (${tablesList.length})'
                                    : (_selectedFilter == 'pending'
                                          ? 'Pending (${pendingTables.length})'
                                          : (_selectedFilter == 'accepted'
                                                ? 'Accepted (${acceptedTables.length})'
                                                : 'Idle (${idleTables.length})')),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'all',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.table_restaurant_rounded,
                                  size: 18,
                                  color: Colors.blueGrey,
                                ),
                                const SizedBox(width: 10),
                                Text('All Tables (${tablesList.length})'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'pending',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.notifications_active_rounded,
                                  size: 18,
                                  color: Color(0xFFE53935),
                                ),
                                const SizedBox(width: 10),
                                Text('Pending 🔴 (${pendingTables.length})'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'accepted',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: Color(0xFF2E7D32),
                                ),
                                const SizedBox(width: 10),
                                Text('Accepted 🟢 (${acceptedTables.length})'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'idle',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  size: 18,
                                  color: Color(0xFFFF9800),
                                ),
                                const SizedBox(width: 10),
                                Text('Idle 🟠 (${idleTables.length})'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (displayList.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 48.0,
                    horizontal: 16.0,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.table_bar_rounded,
                        size: 64,
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedFilter == 'pending'
                            ? 'No pending table requests!'
                            : (tablesList.isEmpty
                                  ? 'Scanning for nearby table devices...'
                                  : 'No tables in this category.'),
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tablesList.isEmpty
                            ? 'Make sure your ESP32 table device is powered on.'
                            : 'Table devices connected via Bluetooth.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            // 3 Tables in One Row (SliverGrid crossAxisCount: 3)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final table = displayList[index];
                  return TableCard(
                    table: table,
                    onTap: () {
                      if (table.isPending) {
                        _showAcceptDialog(table);
                      } else if (table.isAccepted) {
                        _showCompleteDialog(table);
                      }
                    },
                  );
                }, childCount: displayList.length),
              ),
            ),
        ],
      ),
    );
  }
}
