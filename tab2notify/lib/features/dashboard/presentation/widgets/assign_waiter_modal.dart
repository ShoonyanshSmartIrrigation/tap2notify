import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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

  Future<void> _handleAssign() async {
    if (_selectedTableIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one table.'),
          backgroundColor: Color(0xFFE53935),
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
          const SnackBar(
            content: Text('Please enter Waiter Name.'),
            backgroundColor: Color(0xFFE53935),
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
          const SnackBar(
            content: Text('Please select a waiter to assign.'),
            backgroundColor: Color(0xFFE53935),
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
            content: Text(
              '✓ Assigned ${_selectedTableIds.length} Table(s) to $waiterName',
            ),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error assigning waiter: $e'),
            backgroundColor: const Color(0xFFE53935),
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
            content: Text(
              '✓ Removed waiter assignment from ${_selectedTableIds.length} table(s).',
            ),
            backgroundColor: const Color(0xFFFF9800),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing waiter: $e'),
            backgroundColor: const Color(0xFFE53935),
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
    final waitersAsync = ref.watch(waitersStreamProvider);
    final waitersList = waitersAsync.value ?? [];

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Modal Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_add_alt_1_rounded,
                            color: Color(0xFF2E7D32),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assign Waiter',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              'Select table(s) and assign staff',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Scrollable Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Section 1: Select Tables
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '1. Select Table(s) (${_selectedTableIds.length} Selected)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (_selectedTableIds.length == widget.allTables.length) {
                                _selectedTableIds.clear();
                              } else {
                                _selectedTableIds.addAll(
                                  widget.allTables.map((t) => t.id),
                                );
                              }
                            });
                          },
                          child: Text(
                            _selectedTableIds.length == widget.allTables.length
                                ? 'Deselect All'
                                : 'Select All',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Tables Grid / Wrap Selector
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1B26) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.allTables.map((table) {
                          final isSelected = _selectedTableIds.contains(table.id);
                          final hasWaiter = table.isAssigned;

                          return FilterChip(
                            selected: isSelected,
                            avatar: CircleAvatar(
                              backgroundColor: isSelected
                                  ? Colors.white
                                  : (hasWaiter
                                      ? const Color(0xFF2E7D32).withValues(alpha: 0.2)
                                      : Colors.grey.withValues(alpha: 0.2)),
                              radius: 10,
                              child: Text(
                                '${table.tableNumber}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : (hasWaiter
                                          ? const Color(0xFF2E7D32)
                                          : Colors.grey[700]),
                                ),
                              ),
                            ),
                            label: Text(
                              'Table ${table.tableNumber}${hasWaiter ? ' (${table.waiterName.split(' ').first})' : ''}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedTableIds.add(table.id);
                                } else {
                                  _selectedTableIds.remove(table.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Section 2: Choose Waiter
                    const Text(
                      '2. Choose Waiter',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Registered Waiters Radio List
                    ...waitersList.map((waiter) {
                      final isSelected =
                          !_isCustomWaiter && _selectedWaiter?.waiterId == waiter.waiterId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(alpha: 0.1)
                              : (isDark ? const Color(0xFF1E1B26) : Colors.white),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.08)),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            setState(() {
                              _isCustomWaiter = false;
                              _selectedWaiter = waiter;
                            });
                          },
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                            child: Text(
                              waiter.waiterId,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            waiter.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            'ID: ${waiter.waiterId} • ${waiter.tableCount} Active Tables',
                            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: theme.colorScheme.primary,
                                  size: 24,
                                )
                              : const Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  color: Colors.grey,
                                  size: 24,
                                ),
                        ),
                      );
                    }),

                    // Quick Custom Waiter Option
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: _isCustomWaiter
                            ? theme.colorScheme.primary.withValues(alpha: 0.1)
                            : (isDark ? const Color(0xFF1E1B26) : Colors.white),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isCustomWaiter
                              ? theme.colorScheme.primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.08)),
                          width: _isCustomWaiter ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            onTap: () => setState(() => _isCustomWaiter = true),
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                              child: Icon(
                                Icons.edit_note_rounded,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            title: const Text(
                              'Enter Other / New Waiter Name',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                            trailing: _isCustomWaiter
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: theme.colorScheme.primary,
                                    size: 24,
                                  )
                                : const Icon(
                                    Icons.radio_button_unchecked_rounded,
                                    color: Colors.grey,
                                    size: 24,
                                  ),
                          ),
                          if (_isCustomWaiter)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _customIdController,
                                      decoration: InputDecoration(
                                        labelText: 'Waiter ID',
                                        hintText: 'e.g. W004',
                                        isDense: true,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
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

              // Action Buttons Bottom Bar
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
                    if (_selectedTableIds.isNotEmpty)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE53935),
                          side: const BorderSide(color: Color(0xFFE53935)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isLoading ? null : _handleUnassign,
                        child: const Text(
                          'UNASSIGN',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isLoading ? null : _handleAssign,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'ASSIGN ${_selectedTableIds.length} TABLE(S)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
