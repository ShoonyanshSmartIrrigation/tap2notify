import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../service_requests/domain/table_model.dart';
import '../../../service_requests/presentation/service_request_providers.dart';
import '../../../waiter/domain/waiter_model.dart';

class AssignWaiterModal extends ConsumerStatefulWidget {
  final TableModel? initialTable;
  final List<TableModel> allTables;

  const AssignWaiterModal({
    super.key,
    this.initialTable,
    required this.allTables,
  });

  static Future<void> show(
    BuildContext context, {
    TableModel? initialTable,
    required List<TableModel> allTables,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AssignWaiterModal(
        initialTable: initialTable,
        allTables: allTables,
      ),
    );
  }

  @override
  ConsumerState<AssignWaiterModal> createState() => _AssignWaiterModalState();
}

class _AssignWaiterModalState extends ConsumerState<AssignWaiterModal> {
  final Set<String> _selectedTableIds = {};
  WaiterModel? _selectedWaiter;
  final _customNameController = TextEditingController();
  final _customIdController = TextEditingController();
  bool _isCustomWaiter = false;
  bool _isLoading = false;
  String _tableFilter = 'all'; // 'all', 'unassigned', 'assigned'

  @override
  void initState() {
    super.initState();
    if (widget.initialTable != null) {
      _selectedTableIds.add(widget.initialTable!.id);
    }
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _customIdController.dispose();
    super.dispose();
  }

  List<TableModel> _filterTables(List<TableModel> tables) {
    if (_tableFilter == 'unassigned') {
      return tables.where((t) => !t.isAssigned).toList();
    } else if (_tableFilter == 'assigned') {
      return tables.where((t) => t.isAssigned).toList();
    }
    return tables;
  }

  Future<void> _handleAssign() async {
    if (_selectedTableIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Please select at least one table.'),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    String waiterId = '';
    String waiterName = '';

    if (_isCustomWaiter) {
      waiterName = _customNameController.text.trim();
      waiterId = _customIdController.text.trim();
      if (waiterName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please enter Waiter Name.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }
      if (waiterId.isEmpty) {
        waiterId = 'W${DateTime.now().millisecondsSinceEpoch % 1000}';
      }
    } else {
      if (_selectedWaiter == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please choose a waiter to assign.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }
      waiterId = _selectedWaiter!.waiterId;
      waiterName = '${_selectedWaiter!.name} (${_selectedWaiter!.waiterId})';
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      await repo.assignWaiterToTables(
        waiterId: waiterId,
        waiterName: waiterName,
        tableIds: _selectedTableIds.toList(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✓ Assigned ${_selectedTableIds.length} Table(s) to $waiterName',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error assigning waiter: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUnassign() async {
    if (_selectedTableIds.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      for (final id in _selectedTableIds) {
        await repo.removeWaiterFromTable(id);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.person_remove_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✓ Removed waiter from ${_selectedTableIds.length} table(s).',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFFF9800),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing waiter: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    // Real-time streams for dynamic accuracy
    final tablesAsync = ref.watch(tablesStreamProvider);
    final allCurrentTables = tablesAsync.value ?? widget.allTables;
    final waitersAsync = ref.watch(waitersStreamProvider);
    final waitersList = waitersAsync.value ?? [];

    final displayTables = _filterTables(allCurrentTables);
    final unassignedCount = allCurrentTables.where((t) => !t.isAssigned).length;
    final assignedCount = allCurrentTables.where((t) => t.isAssigned).length;

    final hasAssignedTablesSelected = allCurrentTables.any(
      (t) => _selectedTableIds.contains(t.id) && t.isAssigned,
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B26) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) {
          return Column(
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Modal Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 16, 12),
                child: Row(
                  children: [
                    // Gradient Badge
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primaryColor,
                            AppColors.deepOrange,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.assignment_ind_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Title & Subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assign Waiter',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Select tables and assign floor staff',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.6)
                                  : AppColors.lightSecondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Close button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),

              // Scrollable Body
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  children: [
                    // SECTION 1: SELECT TABLES HEADER
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'STEP 1',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: primaryColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Select Tables',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                            if (_selectedTableIds.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_selectedTableIds.length} Selected',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Batch Select/Clear
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          ),
                          onPressed: () {
                            setState(() {
                              if (_selectedTableIds.length == allCurrentTables.length) {
                                _selectedTableIds.clear();
                              } else {
                                _selectedTableIds.addAll(
                                  allCurrentTables.map((t) => t.id),
                                );
                              }
                            });
                          },
                          child: Text(
                            _selectedTableIds.length == allCurrentTables.length
                                ? 'Clear All'
                                : 'Select All',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Quick Table Filter Tabs (All / Unassigned / Assigned)
                    Row(
                      children: [
                        _buildFilterTab(
                          label: 'All (${allCurrentTables.length})',
                          value: 'all',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        const SizedBox(width: 6),
                        _buildFilterTab(
                          label: 'Unassigned ($unassignedCount)',
                          value: 'unassigned',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        const SizedBox(width: 6),
                        _buildFilterTab(
                          label: 'Assigned ($assignedCount)',
                          value: 'assigned',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Table Selection Grid
                    if (displayTables.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF16141D) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'No tables in this category.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.grey,
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1.15,
                        ),
                        itemCount: displayTables.length,
                        itemBuilder: (context, index) {
                          final table = displayTables[index];
                          final isSelected = _selectedTableIds.contains(table.id);
                          final hasWaiter = table.isAssigned;

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedTableIds.remove(table.id);
                                  } else {
                                    _selectedTableIds.add(table.id);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? primaryColor
                                      : (isDark ? const Color(0xFF282433) : const Color(0xFFF8FAFC)),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? primaryColor
                                        : (hasWaiter
                                            ? const Color(0xFF2E7D32).withValues(alpha: 0.35)
                                            : (isDark
                                                ? Colors.white.withValues(alpha: 0.08)
                                                : Colors.black.withValues(alpha: 0.08))),
                                    width: isSelected ? 1.6 : 1.0,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: primaryColor.withValues(alpha: 0.35),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (isSelected)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 3),
                                            child: Icon(
                                              Icons.check_rounded,
                                              size: 13,
                                              color: Colors.white,
                                            ),
                                          ),
                                        Text(
                                          'T-${table.tableNumber}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.white
                                                : (isDark ? Colors.white : Colors.black87),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      hasWaiter
                                          ? table.waiterName.split(' ').first
                                          : 'Unassigned',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: hasWaiter ? FontWeight.w600 : FontWeight.normal,
                                        color: isSelected
                                            ? Colors.white.withValues(alpha: 0.9)
                                            : (hasWaiter
                                                ? (isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
                                                : (isDark ? Colors.white38 : Colors.grey)),
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
                        },
                      ),

                    const SizedBox(height: 24),

                    // SECTION 2: CHOOSE WAITER HEADER
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'STEP 2',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: primaryColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Choose Waiter',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${waitersList.length} Active Staff',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.5)
                                : AppColors.lightSecondaryText,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Registered Waiters List with DYNAMIC ACTIVE TABLE COUNT
                    if (waitersList.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF16141D) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'No registered staff found. Use the quick option below.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...waitersList.map((waiter) {
                        final isSelected =
                            !_isCustomWaiter && _selectedWaiter?.waiterId == waiter.waiterId;

                        // Dynamically calculate assigned tables for this waiter
                        final waiterAssignedTables = allCurrentTables.where((t) {
                          if (t.assignedWaiterId.isNotEmpty && t.assignedWaiterId == waiter.waiterId) {
                            return true;
                          }
                          if (t.waiterName.isNotEmpty) {
                            if (t.waiterName == waiter.waiterId || t.waiterName == waiter.name) {
                              return true;
                            }
                            if (t.waiterName.contains(waiter.waiterId) ||
                                t.waiterName.toLowerCase().contains(waiter.name.toLowerCase())) {
                              return true;
                            }
                          }
                          return false;
                        }).toList();

                        final int activeCount = waiterAssignedTables.length;
                        final String tablesListStr = waiterAssignedTables.isNotEmpty
                            ? ' (${waiterAssignedTables.map((t) => 'T-${t.tableNumber}').join(', ')})'
                            : '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primaryColor.withValues(alpha: 0.08)
                                : (isDark ? const Color(0xFF17151D) : Colors.white),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.08)),
                              width: isSelected ? 1.6 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _isCustomWaiter = false;
                                _selectedWaiter = waiter;
                              });
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  // Waiter Avatar
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? primaryColor
                                          : primaryColor.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      waiter.waiterId,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white : primaryColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Waiter Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          waiter.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              'ID: ${waiter.waiterId}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: isDark
                                                    ? Colors.white.withValues(alpha: 0.6)
                                                    : AppColors.lightSecondaryText,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '•',
                                              style: TextStyle(
                                                color: isDark ? Colors.white30 : Colors.black26,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: activeCount > 0
                                                      ? primaryColor.withValues(alpha: 0.12)
                                                      : (isDark
                                                          ? Colors.white.withValues(alpha: 0.06)
                                                          : Colors.grey.withValues(alpha: 0.12)),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  activeCount > 0
                                                      ? '$activeCount Active Table${activeCount == 1 ? '' : 's'}$tablesListStr'
                                                      : '0 Tables Assigned',
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: activeCount > 0
                                                        ? primaryColor
                                                        : (isDark ? Colors.white54 : Colors.grey[700]),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Checkbox / Radio
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: isSelected ? primaryColor : (isDark ? Colors.white30 : Colors.grey[400]),
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),

                    // Quick Custom Waiter Option
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: _isCustomWaiter
                            ? primaryColor.withValues(alpha: 0.08)
                            : (isDark ? const Color(0xFF17151D) : Colors.white),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isCustomWaiter
                              ? primaryColor
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.08)),
                          width: _isCustomWaiter ? 1.6 : 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () => setState(() => _isCustomWaiter = true),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _isCustomWaiter
                                          ? primaryColor
                                          : (isDark
                                              ? Colors.white.withValues(alpha: 0.06)
                                              : Colors.black.withValues(alpha: 0.05)),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.edit_note_rounded,
                                      color: _isCustomWaiter
                                          ? Colors.white
                                          : (isDark ? Colors.white70 : Colors.black87),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Custom / Temporary Waiter',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Enter custom name and ID for quick assignment',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    _isCustomWaiter
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: _isCustomWaiter
                                        ? primaryColor
                                        : (isDark ? Colors.white30 : Colors.grey[400]),
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isCustomWaiter)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _customNameController,
                                      decoration: InputDecoration(
                                        labelText: 'Waiter Name',
                                        hintText: 'e.g. Sameer',
                                        isDense: true,
                                        prefixIcon: const Icon(Icons.person_outline, size: 18),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _customIdController,
                                      decoration: InputDecoration(
                                        labelText: 'Waiter ID',
                                        hintText: 'e.g. W004',
                                        isDense: true,
                                        prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Action Footer Bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Optional Unassign Button
                    if (hasAssignedTablesSelected || _selectedTableIds.isNotEmpty)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE53935),
                          side: BorderSide(
                            color: const Color(0xFFE53935).withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isLoading ? null : _handleUnassign,
                        icon: const Icon(Icons.person_remove_rounded, size: 16),
                        label: const Text(
                          'UNASSIGN',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (hasAssignedTablesSelected || _selectedTableIds.isNotEmpty)
                      const SizedBox(width: 10),

                    // Primary Assign Button
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: primaryColor.withValues(alpha: 0.4),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isLoading ? null : _handleAssign,
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_rounded, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    _selectedTableIds.isEmpty
                                        ? 'SELECT TABLES'
                                        : 'ASSIGN ${_selectedTableIds.length} TABLE${_selectedTableIds.length > 1 ? 'S' : ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterTab({
    required String label,
    required String value,
    required bool isDark,
    required Color primaryColor,
  }) {
    final isSelected = _tableFilter == value;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _tableFilter = value),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.15)
                  : (isDark
                      ? const Color(0xFF282433)
                      : const Color(0xFFF1F3F5)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.5)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05)),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? primaryColor
                    : (isDark ? Colors.white70 : AppColors.lightSecondaryText),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
