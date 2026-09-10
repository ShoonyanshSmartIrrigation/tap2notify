import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/fcm_service.dart';
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
      ref.read(bleServiceProvider).requestPermissionsAndStartScan();
      _checkInitialRequest();
      final currentWaiter = ref.read(currentLoggedWaiterProvider);
      if (currentWaiter != null && currentWaiter.managerPhone.isNotEmpty) {
        FCMService().syncWaiterToken(currentWaiter.managerPhone, currentWaiter.waiterId);
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

      final tablesAsync =
          ref.read(waiterTablesStreamProvider(currentWaiter.waiterId));
      final tables = tablesAsync.value ?? [];

      final match = tables.where((t) =>
          t.id == reqId ||
          t.tableNumber.toString() == reqId.replaceAll(RegExp(r'[^0-9]'), ''));
      if (match.isNotEmpty) {
        final targetTable = match.first;
        if (targetTable.isPending) {
          _showAcceptDialog(
              targetTable, currentWaiter.name, currentWaiter.waiterId);
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
          actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(dialogContext);

                final repo = ref.read(serviceRequestRepositoryProvider);
                await repo.acceptTableRequest(
                  tableId: table.id,
                  waiterName: waiterName,
                  waiterId: waiterId,
                );

                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('🟢 Table ${table.tableNumber} Request Accepted!'),
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
          actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                      content: Text('✓ Table ${table.tableNumber} marked as Completed & Ready.'),
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
    try {
      await FCMService().unregisterCurrentSession();
    } catch (e) {
      debugPrint('[WAITER SIGN OUT] Error unregistering FCM token: $e');
    }
    await ref.read(currentLoggedWaiterProvider.notifier).setWaiter(null);
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
                    color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.15),
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
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  waiterName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                Text(
                  'Waiter ID: $waiterId • ${assignedTables.length} Tables',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Status',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              HapticFeedback.lightImpact();
              // Restart and force-poll BLE scanner
              await ref.read(bleServiceProvider).startScan();
              // Invalidate waiter stream provider to re-merge
              ref.invalidate(waiterTablesStreamProvider(waiterId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚡ Refreshed table statuses & BLE scanner!'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
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
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFE53935)),
            onPressed: _handleSignOut,
          ),
        ],
      ),
      body: CustomScrollView(
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
                          colors: [
                            Color(0xFFFB923C),
                            Color(0xFFEA580C),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEA580C).withValues(alpha: 0.35),
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
                                  : const Color(0xFF2E7D32),
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
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: Row(
                children: [
                  _buildFilterChip('all', 'All (${assignedTables.length})', null),
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
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        assignedTables.isEmpty
                            ? 'Please ask your Floor Manager to assign tables to your Waiter ID ($waiterId).'
                            : 'Switch filter to view other assigned tables.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5, color: Colors.grey),
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
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final table = displayList[index];
                    return TableCard(
                      table: table,
                      onTap: () {
                        if (table.isPending) {
                          _showAcceptDialog(table, waiterName, waiterId);
                        } else if (table.isAccepted) {
                          _showCompleteDialog(table);
                        }
                      },
                    );
                  },
                  childCount: displayList.length,
                ),
              ),
            ),
        ],
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
}
