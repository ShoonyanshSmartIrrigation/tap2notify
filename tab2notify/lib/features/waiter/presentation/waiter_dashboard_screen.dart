import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/gateway_wifi_service.dart';
import '../../../../core/theme/app_colors.dart';
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

  void _checkInitialRequest([List<TableModel>? currentTables]) {
    final reqId = widget.initialRequestId;
    if (reqId == null || reqId.isEmpty || reqId == _handledRequestId) return;

    void attemptMatch(List<TableModel> tables) {
      if (!mounted) return;
      final currentWaiter = ref.read(currentLoggedWaiterProvider);
      if (currentWaiter == null) return;

      final cleanReqNum = reqId.replaceAll(RegExp(r'[^0-9]'), '');
      final match = tables.where(
        (t) =>
            t.id == reqId ||
            (cleanReqNum.isNotEmpty &&
                t.tableNumber.toString() == cleanReqNum),
      );
      if (match.isNotEmpty) {
        _handledRequestId = reqId;
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
    }

    if (currentTables != null && currentTables.isNotEmpty) {
      attemptMatch(currentTables);
      return;
    }

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final currentWaiter = ref.read(currentLoggedWaiterProvider);
      if (currentWaiter == null) return;

      final tablesAsync = ref.read(
        waiterTablesStreamProvider(currentWaiter.waiterId),
      );
      final tables = tablesAsync.value ?? [];
      attemptMatch(tables);
    });
  }

  // ==========================================
  // MODERN ACTION DIALOGS
  // ==========================================

  void _showAcceptDialog(TableModel table, String waiterName, String waiterId) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hero Calling Icon
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFFEF4444),
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Text(
                'Table ${table.tableNumber} Calling',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Guest requesting immediate assistance',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Accept request for Table ${table.tableNumber} as $waiterName ($waiterId)?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.grey[300] : const Color(0xFF475569),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        _handledRequestId = null;
                        Navigator.pop(dialogContext);
                      },
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF16A34A).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            _handledRequestId = null;
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(dialogContext);

                            final repo =
                                ref.read(waiterServiceRequestRepositoryProvider);
                            await repo.acceptTableRequest(
                              tableId: table.id,
                              waiterName: waiterName,
                              waiterId: waiterId,
                            );

                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '✓ Request accepted for Table ${table.tableNumber} by $waiterName',
                                  ),
                                  backgroundColor: const Color(0xFF16A34A),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text(
                                'ACCEPT REQUEST',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCompleteDialog(TableModel table) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hero Check Icon
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF22C55E),
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Text(
                'Table ${table.tableNumber}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Service Currently in Progress',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Have you served the guest and completed the request for Table ${table.tableNumber}?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.grey[300] : const Color(0xFF475569),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        _handledRequestId = null;
                        Navigator.pop(dialogContext);
                      },
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF16A34A).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            _handledRequestId = null;
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(dialogContext);

                            final repo =
                                ref.read(waiterServiceRequestRepositoryProvider);
                            await repo.resetTableStatus(table.id);

                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '✓ Table ${table.tableNumber} marked as Completed & Ready.',
                                  ),
                                  backgroundColor: const Color(0xFF16A34A),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text(
                                'MARK AS SERVED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showIdleDialog(TableModel table, String waiterName, String waiterId) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.table_restaurant_rounded,
                    color: AppColors.primaryOrange,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Text(
                'Table ${table.tableNumber}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Table Available / Idle',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryOrange,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Assigned Staff: $waiterName\nTap below if guest requests assistance at this table.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.grey[300] : const Color(0xFF475569),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(
                        'Close',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(dialogContext);

                            final repo =
                                ref.read(waiterServiceRequestRepositoryProvider);
                            await repo.triggerTableRequest(
                              table.id,
                              tableNumber: table.tableNumber,
                            );

                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '🔴 Service request triggered for Table ${table.tableNumber}',
                                  ),
                                  backgroundColor: const Color(0xFFEF4444),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.notifications_active_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'CALL SERVICE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
    try {
      GatewayWifiService().clearManagerSession();
    } catch (_) {}
    await waiterNotifier.setWaiter(null);
    if (mounted) {
      context.go('/login');
    }
  }

  // ==========================================
  // MAIN BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentWaiter = ref.watch(currentLoggedWaiterProvider);

    if (currentWaiter == null) {
      return Scaffold(
        backgroundColor:
            isDark ? AppColors.darkBackground : const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primaryOrange),
              const SizedBox(height: 16),
              const Text(
                'Loading Staff Session...',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
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

    ref.listen<AsyncValue<List<TableModel>>>(
      waiterTablesStreamProvider(waiterId),
      (prev, next) {
        final tables = next.value ?? [];
        _checkInitialRequest(tables);
      },
    );

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
      backgroundColor:
          isDark ? AppColors.darkBackground : const Color(0xFFF8FAFC),
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
        toolbarHeight: 64,
        backgroundColor:
            isDark ? AppColors.darkSurface : Colors.white,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Builder(
          builder: (drawerCtx) => InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.lightImpact();
              Scaffold.of(drawerCtx).openDrawer();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  // Waiter Avatar Button / Menu Trigger
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEA580C).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            waiterId,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                      if (pendingTables.isNotEmpty)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? AppColors.darkSurface
                                    : Colors.white,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Center(
                              child: Text(
                                '${pendingTables.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Waiter Info Header
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isConnected
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'FLOOR TERMINAL • ${assignedTables.length} TABLES',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
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
              borderRadius: BorderRadius.circular(14),
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
                  color: isConnected
                      ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                      : const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isConnected
                        ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                        : const Color(0xFFEF4444).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isConnected
                          ? Icons.wifi_rounded
                          : Icons.wifi_find_rounded,
                      size: 16,
                      color: isConnected
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isConnected ? 'Online' : 'Scanning',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isConnected
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryOrange,
        onRefresh: () async {
          HapticFeedback.lightImpact();
          await ref.read(gatewayWifiServiceProvider).refreshDevices();
          ref.invalidate(waiterTablesStreamProvider(waiterId));
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. Hero Floor Status Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: pendingTables.isNotEmpty
                        ? () {
                            HapticFeedback.lightImpact();
                            setState(() => _selectedFilter = 'pending');
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: pendingTables.isNotEmpty
                              ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFFE2E8F0)),
                          width: pendingTables.isNotEmpty ? 1.6 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: pendingTables.isNotEmpty
                                ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                : Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                            blurRadius: pendingTables.isNotEmpty ? 16 : 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Left Icon Squircle
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: pendingTables.isNotEmpty
                                    ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                                    : [const Color(0xFFFB923C), const Color(0xFFEA580C)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: (pendingTables.isNotEmpty
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFFEA580C))
                                      .withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                pendingTables.isNotEmpty
                                    ? Icons.notifications_active_rounded
                                    : Icons.room_service_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Text Status
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'My Floor Station',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: -0.2,
                                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  pendingTables.isNotEmpty
                                      ? '🔴 ${pendingTables.length} Active Request(s) require attention!'
                                      : '✓ All assigned tables are serviced & ready.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: pendingTables.isNotEmpty
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: pendingTables.isNotEmpty
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF16A34A),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Filter pill prompt
                          if (pendingTables.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'VIEW ➔',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 2. Filter Segment Bar
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 6.0,
                ),
                child: Row(
                  children: [
                    _buildModernFilterPill(
                      value: 'all',
                      label: 'All Tables',
                      count: assignedTables.length,
                      accentColor: AppColors.primaryOrange,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildModernFilterPill(
                      value: 'pending',
                      label: 'Calling 🔴',
                      count: pendingTables.length,
                      accentColor: const Color(0xFFEF4444),
                      isDark: isDark,
                      highlightAlert: pendingTables.isNotEmpty,
                    ),
                    const SizedBox(width: 8),
                    _buildModernFilterPill(
                      value: 'accepted',
                      label: 'Accepted 🟢',
                      count: acceptedTables.length,
                      accentColor: const Color(0xFF22C55E),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildModernFilterPill(
                      value: 'idle',
                      label: 'Idle 🟠',
                      count: idleTables.length,
                      accentColor: const Color(0xFFF57C00),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 6)),

            // 3. Empty State or 3-Column Table Grid
            if (displayList.isEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 56.0,
                      horizontal: 24.0,
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primaryOrange.withValues(
                              alpha: isDark ? 0.15 : 0.1,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.table_restaurant_outlined,
                              size: 36,
                              color: AppColors.primaryOrange,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          assignedTables.isEmpty
                              ? 'No tables currently assigned to $waiterId'
                              : 'No tables in this status',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          assignedTables.isEmpty
                              ? 'Ask your Floor Manager to assign restaurant tables to your Waiter ID ($waiterId).'
                              : 'Tap "All Tables" above to view all floor stations.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 48.0),
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
                        HapticFeedback.lightImpact();
                        if (table.isPending) {
                          _showAcceptDialog(table, waiterName, waiterId);
                        } else if (table.isAccepted) {
                          _showCompleteDialog(table);
                        } else {
                          _showIdleDialog(table, waiterName, waiterId);
                        }
                      },
                    );
                  }, childCount: displayList.length),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // MODERN FILTER PILL
  // ==========================================
  Widget _buildModernFilterPill({
    required String value,
    required String label,
    required int count,
    required Color accentColor,
    required bool isDark,
    bool highlightAlert = false,
  }) {
    final isSelected = _selectedFilter == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedFilter = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor
                : (isDark
                    ? AppColors.darkSurface
                    : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : (highlightAlert
                      ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0))),
              width: highlightAlert && !isSelected ? 1.5 : 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.grey[300] : const Color(0xFF334155)),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? Colors.white : accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // GATEWAY DIAGNOSTICS MODAL
  // ==========================================
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
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
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
                          color: (isConnected
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFEF4444))
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isConnected
                              ? Icons.wifi_rounded
                              : Icons.wifi_find_rounded,
                          color: isConnected
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Gateway Telemetry',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Status',
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
                isConnected ? const Color(0xFF22C55E) : const Color(0xFFF57C00),
              ),
              _buildDiagRow(
                'Gateway IP Address',
                gatewayIp.isNotEmpty ? '$gatewayIp:80' : 'Auto-discovery',
                isDark ? Colors.white70 : Colors.black87,
              ),
              _buildDiagRow(
                'Assigned Devices',
                '${tables.where((t) => t.isDeviceOnline).length} / ${tables.length} Tables Online',
                isDark ? Colors.white : Colors.black87,
              ),
              const SizedBox(height: 12),
              const Text(
                'ESP32-WROOM Gateway communicates over local Wi-Fi with sub-5ms event dispatching.',
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

  // ==========================================
  // MODERN WAITER DRAWER
  // ==========================================
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
      backgroundColor:
          isDark ? const Color(0xFF141218) : const Color(0xFFF8FAFC),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. Profile Header Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
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
                        colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEA580C).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        waiterId,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
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
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
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
                                color: AppColors.primaryOrange.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ID: $waiterId',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryOrange,
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
                                color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: Color(0xFF22C55E),
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'On Duty',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF22C55E),
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
            const SizedBox(height: 16),

            // 2. Floor Overview Stat Grid
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'FLOOR OVERVIEW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: AppColors.primaryOrange,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDrawerStatTile(
                          title: 'Calling',
                          count: pendingTables.length,
                          color: const Color(0xFFEF4444),
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
                          color: const Color(0xFF22C55E),
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
                          color: const Color(0xFFF57C00),
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
            const SizedBox(height: 16),

            // 3. Preferences Section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'PREFERENCES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: AppColors.primaryOrange,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    size: 18,
                    color: AppColors.primaryOrange,
                  ),
                ),
                title: const Text(
                  'Dark Theme',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                trailing: Switch.adaptive(
                  value: isDark,
                  activeTrackColor: AppColors.primaryOrange,
                  onChanged: (_) {
                    ref.read(themeModeProvider.notifier).toggleTheme();
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Wi-Fi Gateway Telemetry Box
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'GATEWAY TELEMETRY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: AppColors.primaryOrange,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isConnected
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFEF4444))
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isConnected
                              ? Icons.wifi_rounded
                              : Icons.wifi_find_rounded,
                          size: 18,
                          color: isConnected
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
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
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              gatewayIp.isNotEmpty
                                  ? 'IP: $gatewayIp:80'
                                  : 'Auto-discovery active',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: AppColors.primaryOrange.withValues(alpha: 0.3),
                        ),
                      ),
                      icon: const Icon(
                        Icons.analytics_outlined,
                        size: 16,
                        color: AppColors.primaryOrange,
                      ),
                      label: const Text(
                        'Open Diagnostics',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryOrange,
                        ),
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
            const SizedBox(height: 18),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.pop(context);
                _handleSignOut();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 13,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w900,
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
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(14),
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
                    fontSize: 16,
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
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey[300] : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
