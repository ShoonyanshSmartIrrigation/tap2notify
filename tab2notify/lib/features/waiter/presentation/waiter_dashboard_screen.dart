import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/gateway_wifi_service.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/widgets/table_card.dart';
import '../../service_requests/domain/table_model.dart';
import '../../service_requests/presentation/service_request_providers.dart';

class WaiterDashboardScreen extends ConsumerStatefulWidget {
  final String? initialRequestId;

  const WaiterDashboardScreen({super.key, this.initialRequestId});

  @override
  ConsumerState<WaiterDashboardScreen> createState() =>
      _WaiterDashboardScreenState();
}

class _WaiterDashboardScreenState extends ConsumerState<WaiterDashboardScreen> {
  String _selectedFilter = 'all'; // 'all', 'pending', 'accepted', 'idle'
  String? _handledRequestId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gatewayWifiServiceProvider).startScan();
      _checkInitialRequest();
      final currentWaiter = ref.read(currentLoggedWaiterProvider);
      if (currentWaiter != null && currentWaiter.managerPhone.isNotEmpty) {
        FCMService().syncWaiterToken(
          currentWaiter.managerPhone,
          currentWaiter.waiterId,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant WaiterDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRequestId != null &&
        widget.initialRequestId != oldWidget.initialRequestId) {
      _checkInitialRequest();
    }
  }

  void _checkInitialRequest() {
    final reqId = widget.initialRequestId;
    if (reqId == null || reqId.isEmpty || reqId == _handledRequestId) return;
    _handledRequestId = reqId;

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final currentWaiter = ref.read(currentLoggedWaiterProvider);
      if (currentWaiter == null) return;

      final tablesAsync = ref.read(
        waiterTablesStreamProvider(currentWaiter.waiterId),
      );
      final tables = tablesAsync.value ?? [];

      final match = tables.where(
        (t) =>
            t.id == reqId ||
            t.tableNumber.toString() == reqId.replaceAll(RegExp(r'[^0-9]'), ''),
      );
      if (match.isNotEmpty) {
        final targetTable = match.first;
        if (targetTable.isPending) {
          _showAcceptDialog(
            targetTable,
            currentWaiter.name,
            currentWaiter.waiterId,
          );
        } else if (targetTable.isAccepted) {
          _showCompleteDialog(targetTable);
        }
      }
    });
  }

  void _showAcceptDialog(TableModel table, String waiterName, String waiterId) {
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
                  Icons.notifications_active_rounded,
                  color: Color(0xFFE53935),
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Table ${table.tableNumber} Calling',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Guest is requesting immediate service 🔴',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          content: Text(
            'Accept request for Table ${table.tableNumber} as $waiterName ($waiterId)?',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
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
                Navigator.pop(dialogContext);

                final repo = ref.read(waiterServiceRequestRepositoryProvider);
                await repo.acceptTableRequest(
                  tableId: table.id,
                  waiterName: waiterName,
                  waiterId: waiterId,
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
                'Request is in progress 🟢',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
          content: const Text(
            'Have you served the guest and completed the request?',
            textAlign: TextAlign.center,
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
                Navigator.pop(dialogContext);

                final repo = ref.read(waiterServiceRequestRepositoryProvider);
                await repo.resetTableStatus(table.id);

                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '✓ Table ${table.tableNumber} marked as Completed & Ready.',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text(
                'MARK AS SERVED / COMPLETED',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleSignOut() async {
    final waiterNotifier = ref.read(currentLoggedWaiterProvider.notifier);
    try {
      await FCMService().unregisterCurrentSession();
    } catch (e) {
      debugPrint('[WAITER SIGN OUT] Error unregistering FCM token: $e');
    }
    await waiterNotifier.setWaiter(null);
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentWaiter = ref.watch(currentLoggedWaiterProvider);

    if (currentWaiter == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Loading Staff Session...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Return to Staff Login'),
              ),
            ],
          ),
        ),
      );
    }

    final waiterId = currentWaiter.waiterId;
    final waiterName = currentWaiter.name;

    final wifiService = ref.watch(gatewayWifiServiceProvider);
    final connectionStatus =
        ref.watch(gatewayConnectionStatusStreamProvider).value ??
        wifiService.connectionStatus;
    final isScanning = ref.watch(gatewayScanningStreamProvider).value ?? false;
    final isConnected = connectionStatus == GatewayConnectionStatus.connected;

    final tablesAsync = ref.watch(waiterTablesStreamProvider(waiterId));
    final assignedTables = tablesAsync.value ?? [];

    final pendingTables = assignedTables.where((t) => t.isPending).toList();
    final acceptedTables = assignedTables.where((t) => t.isAccepted).toList();
    final idleTables = assignedTables.where((t) => t.isIdle).toList();

    List<TableModel> displayList = [];
    if (_selectedFilter == 'pending') {
      displayList = pendingTables;
    } else if (_selectedFilter == 'accepted') {
      displayList = acceptedTables;
    } else if (_selectedFilter == 'idle') {
      displayList = idleTables;
    } else {
      displayList = assignedTables;
    }

    return Scaffold(
      drawer: _buildWaiterDrawer(
        context: context,
        theme: theme,
        isDark: isDark,
        waiterName: waiterName,
        waiterId: waiterId,
        assignedTables: assignedTables,
        pendingTables: pendingTables,
        acceptedTables: acceptedTables,
        idleTables: idleTables,
        isConnected: isConnected,
        isScanning: isScanning,
        connectionStatus: connectionStatus,
        gatewayIp: wifiService.gatewayIp,
      ),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 62,
        backgroundColor: isDark ? const Color(0xFF141218) : Colors.white,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Builder(
          builder: (drawerCtx) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              HapticFeedback.lightImpact();
              Scaffold.of(drawerCtx).openDrawer();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1B26)
                              : const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(
                                alpha: isDark ? 0.25 : 0.15,
                              ),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
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
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.restaurant_rounded,
                                    color: theme.colorScheme.primary,
                                    size: 22,
                                  ),
                            ),
                          ),
                        ),
                      ),
                      if (pendingTables.isNotEmpty)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF141218)
                                    : Colors.white,
                                width: 1.5,
                              ),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 17,
                              minHeight: 17,
                            ),
                            child: Center(
                              child: Text(
                                '${pendingTables.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                waiterName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isConnected
                                    ? const Color.fromARGB(255, 49, 233, 58)
                                    : const Color(0xFFE53935),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'ID: $waiterId • ${assignedTables.length} Tables',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          // Wi-Fi Gateway Connectivity Status Box
          Padding(
            padding: const EdgeInsets.only(right: 14.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                HapticFeedback.lightImpact();
                _showGatewayInfoModal(
                  assignedTables,
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
                  color:
                      (isConnected
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFE53935))
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        (isConnected
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFE53935))
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
                      size: 18,
                      color: isConnected
                          ? const Color.fromARGB(255, 49, 233, 58)
                          : const Color(0xFFE53935),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.lightImpact();
          // Refresh Wi-Fi Gateway devices
          await ref.read(gatewayWifiServiceProvider).refreshDevices();
          // Invalidate waiter stream provider to re-merge
          ref.invalidate(waiterTablesStreamProvider(waiterId));
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Hero Banner for Waiter
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFEA580C,
                              ).withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            waiterId,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'My Assigned Floor Tables',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              pendingTables.isNotEmpty
                                  ? '🔴 ${pendingTables.length} Active Request(s) require attention!'
                                  : '✓ All assigned tables are serviced & ready.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: pendingTables.isNotEmpty
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: pendingTables.isNotEmpty
                                    ? const Color(0xFFE53935)
                                    : const Color.fromARGB(255, 60, 218, 68),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Filter Row
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 6.0,
                ),
                child: Row(
                  children: [
                    _buildFilterChip(
                      'all',
                      'All (${assignedTables.length})',
                      null,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'pending',
                      'Pending 🔴 (${pendingTables.length})',
                      const Color(0xFFE53935),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'accepted',
                      'Accepted 🟢 (${acceptedTables.length})',
                      const Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'idle',
                      'Idle 🟠 (${idleTables.length})',
                      const Color(0xFFFF9800),
                    ),
                  ],
                ),
              ),
            ),

            // Empty State or Tables Grid
            if (displayList.isEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 60.0,
                      horizontal: 20.0,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.table_restaurant_outlined,
                          size: 64,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          assignedTables.isEmpty
                              ? 'No tables currently assigned to $waiterId.'
                              : 'No tables match this filter.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          assignedTables.isEmpty
                              ? 'Please ask your Floor Manager to assign tables to your Waiter ID ($waiterId).'
                              : 'Switch filter to view other assigned tables.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 40.0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final table = displayList[index];
                    return TableCard(table: table);
                  }, childCount: displayList.length),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, Color? color) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : color,
        ),
      ),
      selected: isSelected,
      selectedColor: color ?? Theme.of(context).colorScheme.primary,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = value);
        }
      },
    );
  }

  void _showGatewayInfoModal(
    List<TableModel> tables,
    bool isScanning,
    GatewayConnectionStatus status,
    String gatewayIp,
  ) {
    final isConnected = status == GatewayConnectionStatus.connected;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                        isConnected
                            ? Icons.wifi_rounded
                            : Icons.wifi_find_rounded,
                        color: isConnected
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE53935),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Gateway Wi-Fi Telemetry',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Gateway Status',
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
                'Assigned Devices',
                '${tables.where((t) => t.isDeviceOnline).length} / ${tables.length} Tables Online',
                isDark ? Colors.white : Colors.black87,
              ),
              const SizedBox(height: 12),
              const Text(
                'ESP32-WROOM Gateway communicates over local Wi-Fi with instant sub-5ms event dispatching.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
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
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
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

  Widget _buildWaiterDrawer({
    required BuildContext context,
    required ThemeData theme,
    required bool isDark,
    required String waiterName,
    required String waiterId,
    required List<TableModel> assignedTables,
    required List<TableModel> pendingTables,
    required List<TableModel> acceptedTables,
    required List<TableModel> idleTables,
    required bool isConnected,
    required bool isScanning,
    required GatewayConnectionStatus connectionStatus,
    required String gatewayIp,
  }) {
    return Drawer(
      backgroundColor: isDark
          ? const Color(0xFF141218)
          : const Color(0xFFFBFBFB),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. Drawer Header Profile Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF261D1A), const Color(0xFF1E1B26)]
                      : [const Color(0xFFFFF3E0), Colors.white],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Avatar Circle
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFEA580C,
                          ).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          waiterName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ID: $waiterId',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF2E7D32,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: Color(0xFF2E7D32),
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'On Duty',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. Floor Status Box
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'FLOOR OVERVIEW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDrawerStatTile(
                          title: 'Pending',
                          count: pendingTables.length,
                          color: const Color(0xFFE53935),
                          icon: Icons.notifications_active_rounded,
                          isDark: isDark,
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _selectedFilter = 'pending');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDrawerStatTile(
                          title: 'Accepted',
                          count: acceptedTables.length,
                          color: const Color(0xFF2E7D32),
                          icon: Icons.check_circle_rounded,
                          isDark: isDark,
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _selectedFilter = 'accepted');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDrawerStatTile(
                          title: 'Idle Tables',
                          count: idleTables.length,
                          color: const Color(0xFFFF9800),
                          icon: Icons.pause_circle_rounded,
                          isDark: isDark,
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _selectedFilter = 'idle');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDrawerStatTile(
                          title: 'All Assigned',
                          count: assignedTables.length,
                          color: const Color(0xFF0284C7),
                          icon: Icons.table_restaurant_rounded,
                          isDark: isDark,
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _selectedFilter = 'all');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 4. Quick Actions / Preferences
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'PREFERENCES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isDark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: const Text(
                      'Dark Mode',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Switch.adaptive(
                      value: isDark,
                      activeTrackColor: theme.colorScheme.primary,
                      onChanged: (_) {
                        ref.read(themeModeProvider.notifier).toggleTheme();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 3. Wi-Fi Gateway Telemetry Box
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'GATEWAY TELEMETRY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              (isConnected
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFE53935))
                                  .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isConnected
                              ? Icons.wifi_rounded
                              : Icons.wifi_find_rounded,
                          size: 18,
                          color: isConnected
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFE53935),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isConnected
                                  ? 'Gateway Connected'
                                  : 'Searching Gateway...',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              gatewayIp.isNotEmpty
                                  ? 'IP: $gatewayIp:80'
                                  : 'Auto-discovery active',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.analytics_outlined, size: 16),
                      label: const Text(
                        'Open Diagnostics',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _showGatewayInfoModal(
                          assignedTables,
                          isScanning,
                          connectionStatus,
                          gatewayIp,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // 5. Drawer Footer: Sign Out Button
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(context);
                _handleSignOut();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFE53935).withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFE53935),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerStatTile({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 16, color: color),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
