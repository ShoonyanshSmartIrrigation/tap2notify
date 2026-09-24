import 'package:flutter/material.dart';

import '../../../../core/services/gateway_wifi_service.dart';
import '../../../../core/widgets/app_info_card.dart';
import '../../../../core/widgets/table_card.dart';
import '../../../service_requests/domain/table_model.dart';
import '../widgets/table_unlock_dialog.dart';

class TablesTabView extends StatelessWidget {
  final List<TableModel> tablesList;
  final List<TableModel> unlockedTables;
  final List<TableModel> lockedTables;
  final List<TableModel> displayList;
  final List<TableModel> pendingTables;
  final List<TableModel> acceptedTables;
  final List<TableModel> idleTables;
  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;
  final bool isScanning;
  final GatewayConnectionStatus connectionStatus;
  final VoidCallback onGatewayInfoTap;
  final VoidCallback onConfigureTables;
  final VoidCallback onManageWaiters;
  final VoidCallback onAssignWaiters;
  final void Function(TableModel table)? onTableTap;

  const TablesTabView({
    super.key,
    required this.tablesList,
    required this.unlockedTables,
    required this.lockedTables,
    required this.displayList,
    required this.pendingTables,
    required this.acceptedTables,
    required this.idleTables,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.isScanning,
    this.connectionStatus = GatewayConnectionStatus.connected,
    required this.onGatewayInfoTap,
    required this.onConfigureTables,
    required this.onManageWaiters,
    required this.onAssignWaiters,
    this.onTableTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modern App Information Hero Card
                const AppInfoCard(),
                const SizedBox(height: 12),

                // Manager Fast Action Bar (Configure Tables, Waiters, Assign)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
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
                      // Configure Total Tables
                      Expanded(
                        child: InkWell(
                          onTap: onConfigureTables,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.tune_rounded,
                                    color: theme.colorScheme.primary,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Set Tables',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(width: 1, height: 32, color: Colors.grey.withValues(alpha: 0.2)),

                      // Assign Waiters
                      Expanded(
                        child: InkWell(
                          onTap: onAssignWaiters,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.assignment_ind_rounded,
                                    color: theme.colorScheme.primary,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Assign Staff',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(width: 1, height: 32, color: Colors.grey.withValues(alpha: 0.2)),

                      // Manage Waiters
                      Expanded(
                        child: InkWell(
                          onTap: onManageWaiters,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.group_rounded,
                                    color: theme.colorScheme.primary,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Waiters',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Hotel Tables Section Title & Filter Dropdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      selectedFilter == 'locked'
                          ? 'Locked Tables (${lockedTables.length})'
                          : (selectedFilter == 'all'
                              ? 'Hotel Tables (${unlockedTables.length})'
                              : 'Hotel Tables (${displayList.length})'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Theme(
                      data: theme.copyWith(
                        splashFactory: NoSplash.splashFactory,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                      ),
                      child: PopupMenuButton<String>(
                        borderRadius: BorderRadius.circular(20),
                        tooltip: 'Filter Tables',
                        initialValue: selectedFilter,
                        onSelected: onFilterChanged,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: selectedFilter == 'locked'
                                ? const Color(0xFFEA580C).withValues(alpha: 0.15)
                                : theme.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selectedFilter == 'locked'
                                  ? const Color(0xFFEA580C).withValues(alpha: 0.4)
                                  : theme.colorScheme.primary.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                selectedFilter == 'locked'
                                    ? Icons.lock_rounded
                                    : Icons.filter_list_rounded,
                                size: 16,
                                color: selectedFilter == 'locked'
                                    ? const Color(0xFFEA580C)
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                selectedFilter == 'all'
                                    ? 'All (${unlockedTables.length})'
                                    : (selectedFilter == 'pending'
                                        ? 'Pending (${pendingTables.length})'
                                        : (selectedFilter == 'accepted'
                                            ? 'Accepted (${acceptedTables.length})'
                                            : (selectedFilter == 'assigned'
                                                ? 'Assigned (${unlockedTables.where((t) => t.isAssigned).length})'
                                                : (selectedFilter == 'unassigned'
                                                    ? 'Unassigned (${unlockedTables.where((t) => !t.isAssigned).length})'
                                                    : (selectedFilter == 'locked'
                                                        ? 'Locked 🔒 (${lockedTables.length})'
                                                        : (selectedFilter == 'unlocked'
                                                            ? 'Unlocked 🔓 (${unlockedTables.length})'
                                                            : 'Idle (${idleTables.length})')))))),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: selectedFilter == 'locked'
                                      ? const Color(0xFFEA580C)
                                      : theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                size: 18,
                                color: selectedFilter == 'locked'
                                    ? const Color(0xFFEA580C)
                                    : theme.colorScheme.primary,
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
                                Text('All Tables (${unlockedTables.length})'),
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
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'locked',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lock_rounded,
                                  size: 18,
                                  color: Color(0xFFEA580C),
                                ),
                                const SizedBox(width: 10),
                                Text('Locked Tables 🔒 (${lockedTables.length})'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'unlocked',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lock_open_rounded,
                                  size: 18,
                                  color: Color(0xFF2E7D32),
                                ),
                                const SizedBox(width: 10),
                                Text('Unlocked Tables 🔓 (${unlockedTables.length})'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'assigned',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person_rounded,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Text('Assigned Tables 👤 (${unlockedTables.where((t) => t.isAssigned).length})'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'unassigned',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_off_rounded,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 10),
                                Text('Unassigned Tables ⚠️ (${unlockedTables.where((t) => !t.isAssigned).length})'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // Empty state or 3-Column Grid
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
                      selectedFilter == 'locked'
                          ? Icons.lock_open_rounded
                          : Icons.table_bar_rounded,
                      size: 64,
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      selectedFilter == 'pending'
                          ? 'No pending table requests!'
                          : (selectedFilter == 'locked'
                              ? 'No locked tables!'
                              : (unlockedTables.isEmpty
                                  ? (lockedTables.isNotEmpty
                                      ? 'All ${lockedTables.length} table(s) are currently locked.'
                                      : 'Scanning for nearby table devices...')
                                  : 'No tables in this category.')),
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedFilter == 'locked'
                          ? 'All configured tables are authorized & unlocked.'
                          : (unlockedTables.isEmpty && lockedTables.isNotEmpty
                              ? 'Switch to the "Locked 🔒" filter to unlock your tables with password.'
                              : (tablesList.isEmpty
                                  ? 'Make sure your ESP32 table device is powered on.'
                                  : 'Table devices connected via Wi-Fi Gateway.')),
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
          // 3 Tables per row
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 100.0),
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
                    isManagerView: true,
                    onUnlock: () => TableUnlockDialog.show(context, table),
                    onTap: onTableTap != null ? () => onTableTap!(table) : null,
                  );
                },
                childCount: displayList.length,
              ),
            ),
          ),
      ],
    );
  }
}
