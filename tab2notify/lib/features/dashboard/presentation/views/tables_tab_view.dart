import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/gateway_wifi_service.dart';
import '../../../../core/theme/app_colors.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. App Info / How it Works Card
                const AppInfoCard(),
                const SizedBox(height: 12),

                // 2. Manager Fast Action Bar
                _buildFastActionBar(context, theme, isDark),
                const SizedBox(height: 16),

                // 3. Section Title & Filter Dropdown Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      selectedFilter == 'locked'
                          ? 'Locked Tables (${lockedTables.length})'
                          : (selectedFilter == 'all'
                              ? 'Floor Tables (${unlockedTables.length})'
                              : 'Filtered Tables (${displayList.length})'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: -0.3,
                      ),
                    ),

                    // More Filters Dropdown
                    _buildMoreFiltersMenu(context, theme, isDark),
                  ],
                ),
                const SizedBox(height: 10),

                // 4. Quick Horizontal Pill Filters
                _buildQuickFilterRow(theme, isDark),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),

        // 5. Empty State or 3-Column Table Grid
        if (displayList.isEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 48.0,
                  horizontal: 20.0,
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
                      child: Center(
                        child: Icon(
                          selectedFilter == 'locked'
                              ? Icons.lock_open_rounded
                              : Icons.table_restaurant_rounded,
                          size: 36,
                          color: AppColors.primaryOrange,
                        ),
                      ),
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
                                  : 'No tables in this status.')),
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
                      selectedFilter == 'locked'
                          ? 'All configured tables are authorized & unlocked.'
                          : (unlockedTables.isEmpty && lockedTables.isNotEmpty
                              ? 'Switch to the "Locked 🔒" filter to unlock your tables with password.'
                              : (tablesList.isEmpty
                                  ? 'Make sure your ESP32 table hardware is powered on and connected.'
                                  : 'Tap "All Tables" above to view active floor tables.')),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                    if (tablesList.isEmpty) ...[
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          TableUnlockDialog.show(context);
                        },
                        icon: const Icon(Icons.verified_user_rounded, size: 18),
                        label: const Text(
                          'VERIFY DEVICE OWNERSHIP',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            fontSize: 12.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
        else
          // 3 Tables per row
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16.0, 4, 16.0, 110.0),
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
                    onUnlock: () {
                      HapticFeedback.lightImpact();
                      TableUnlockDialog.show(context, table);
                    },
                  );
                },
                childCount: displayList.length,
              ),
            ),
          ),
      ],
    );
  }

  // ==========================================
  // FAST ACTION BAR
  // ==========================================
  Widget _buildFastActionBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
          // 1. Verify Device Ownership
          _buildActionButton(
            label: 'Verify Device',
            icon: Icons.verified_user_rounded,
            color: const Color(0xFF22C55E),
            onTap: () {
              HapticFeedback.lightImpact();
              TableUnlockDialog.show(context);
            },
          ),
          Container(
            width: 1,
            height: 32,
            color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          ),

          // 2. Set Total Tables
          _buildActionButton(
            label: 'Set Tables',
            icon: Icons.tune_rounded,
            color: AppColors.primaryOrange,
            onTap: () {
              HapticFeedback.lightImpact();
              onConfigureTables();
            },
          ),
          Container(
            width: 1,
            height: 32,
            color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          ),

          // 3. Assign Staff
          _buildActionButton(
            label: 'Assign Staff',
            icon: Icons.assignment_ind_rounded,
            color: const Color(0xFF0284C7),
            onTap: () {
              HapticFeedback.lightImpact();
              onAssignWaiters();
            },
          ),
          Container(
            width: 1,
            height: 32,
            color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          ),

          // 4. Manage Waiters
          _buildActionButton(
            label: 'Waiters',
            icon: Icons.group_rounded,
            color: const Color(0xFF8B5CF6),
            onTap: () {
              HapticFeedback.lightImpact();
              onManageWaiters();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(icon, color: color, size: 19),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // QUICK HORIZONTAL FILTER PILLS
  // ==========================================
  Widget _buildQuickFilterRow(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip(
            value: 'all',
            label: 'All Tables',
            count: unlockedTables.length,
            color: AppColors.primaryOrange,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            value: 'pending',
            label: 'Calling 🔴',
            count: pendingTables.length,
            color: const Color(0xFFEF4444),
            isDark: isDark,
            highlight: pendingTables.isNotEmpty,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            value: 'accepted',
            label: 'Accepted 🟢',
            count: acceptedTables.length,
            color: const Color(0xFF22C55E),
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            value: 'idle',
            label: 'Idle 🟠',
            count: idleTables.length,
            color: const Color(0xFFF57C00),
            isDark: isDark,
          ),
          if (lockedTables.isNotEmpty) ...[
            const SizedBox(width: 8),
            _buildFilterChip(
              value: 'locked',
              label: 'Locked 🔒',
              count: lockedTables.length,
              color: const Color(0xFFEA580C),
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String value,
    required String label,
    required int count,
    required Color color,
    required bool isDark,
    bool highlight = false,
  }) {
    final isSelected = selectedFilter == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onFilterChanged(value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? color
                : (isDark ? AppColors.darkSurface : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? color
                  : (highlight
                      ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0))),
              width: highlight && !isSelected ? 1.5 : 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
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
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? Colors.white : color,
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
  // MORE FILTERS DROPDOWN MENU
  // ==========================================
  Widget _buildMoreFiltersMenu(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: PopupMenuButton<String>(
        borderRadius: BorderRadius.circular(20),
        tooltip: 'More Filters',
        initialValue: selectedFilter,
        onSelected: (val) {
          HapticFeedback.selectionClick();
          onFilterChanged(val);
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selectedFilter == 'assigned' || selectedFilter == 'unassigned'
                ? AppColors.primaryOrange.withValues(alpha: 0.15)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selectedFilter == 'assigned' ||
                      selectedFilter == 'unassigned'
                  ? AppColors.primaryOrange.withValues(alpha: 0.4)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 15,
                color: selectedFilter == 'assigned' ||
                        selectedFilter == 'unassigned'
                    ? AppColors.primaryOrange
                    : (isDark ? Colors.white70 : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 4),
              Text(
                selectedFilter == 'assigned'
                    ? 'Assigned'
                    : (selectedFilter == 'unassigned' ? 'Unassigned' : 'Filter'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selectedFilter == 'assigned' ||
                          selectedFilter == 'unassigned'
                      ? AppColors.primaryOrange
                      : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
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
                  color: Color(0xFFEF4444),
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
                  color: Color(0xFF22C55E),
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
                  color: Color(0xFFF57C00),
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
                  color: Color(0xFF22C55E),
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
                const Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: AppColors.primaryOrange,
                ),
                const SizedBox(width: 10),
                Text(
                  'Assigned Tables (${unlockedTables.where((t) => t.isAssigned).length})',
                ),
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
                Text(
                  'Unassigned Tables (${unlockedTables.where((t) => !t.isAssigned).length})',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
