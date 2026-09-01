import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../../core/widgets/app_info_card.dart';
import '../../../../core/widgets/table_card.dart';
import '../../../service_requests/domain/table_model.dart';

class TablesTabView extends StatelessWidget {
  final List<TableModel> tablesList;
  final List<TableModel> displayList;
  final List<TableModel> pendingTables;
  final List<TableModel> acceptedTables;
  final List<TableModel> idleTables;
  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<TableModel> onTableTap;
  final bool isScanning;
  final BluetoothAdapterState adapterState;
  final VoidCallback onBleInfoTap;

  const TablesTabView({
    super.key,
    required this.tablesList,
    required this.displayList,
    required this.pendingTables,
    required this.acceptedTables,
    required this.idleTables,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.onTableTap,
    required this.isScanning,
    required this.adapterState,
    required this.onBleInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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

                // Hotel Tables Section Title & Filter Dropdown
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
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.3),
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
                              selectedFilter == 'all'
                                  ? 'All (${tablesList.length})'
                                  : (selectedFilter == 'pending'
                                      ? 'Pending (${pendingTables.length})'
                                      : (selectedFilter == 'accepted'
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
                      Icons.table_bar_rounded,
                      size: 64,
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      selectedFilter == 'pending'
                          ? 'No pending table requests!'
                          : (tablesList.isEmpty
                              ? 'Scanning for nearby table devices...'
                              : 'No tables in this category.'),
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                    onTap: () => onTableTap(table),
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
