import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_requests/presentation/service_request_providers.dart';
import '../../../waiter/domain/waiter_model.dart';

class WaiterManagementSheet extends ConsumerStatefulWidget {
  const WaiterManagementSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => const WaiterManagementSheet(),
    );
  }

  @override
  ConsumerState<WaiterManagementSheet> createState() =>
      _WaiterManagementSheetState();
}

class _WaiterManagementSheetState extends ConsumerState<WaiterManagementSheet> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController(text: '1234');
  bool _isAdding = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateWaiter() async {
    final name = _nameController.text.trim();
    final id = _idController.text.trim().toUpperCase();
    final pin = _pinController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Waiter Name and Waiter ID.'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final newWaiter = WaiterModel(
        waiterId: id,
        name: name,
        phone: phone,
        passcode: pin.isNotEmpty ? pin : '1234',
        status: 'active',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final repo = ref.read(serviceRequestRepositoryProvider);
      await repo.saveWaiter(newWaiter);

      _nameController.clear();
      _idController.clear();
      _phoneController.clear();
      _pinController.text = '1234';

      setState(() => _isAdding = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Waiter $name ($id) registered successfully!'),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating waiter: $e'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDeleteWaiter(WaiterModel waiter) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete ${waiter.name}?'),
        content: Text(
          'This will remove ${waiter.name} (${waiter.waiterId}) and unassign all their tables.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final repo = ref.read(serviceRequestRepositoryProvider);
      await repo.deleteWaiter(waiter.waiterId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Removed ${waiter.name}'),
            backgroundColor: const Color(0xFFFF9800),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final waitersAsync = ref.watch(waitersStreamProvider);
    final waitersList = waitersAsync.value ?? [];
    final tablesAsync = ref.watch(tablesStreamProvider);
    final allTables = tablesAsync.value ?? [];

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

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.15,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.badge_rounded,
                            color: theme.colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Floor Waiters & Staff',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              '${waitersList.length} Registered Staff Members',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
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

              // Content List
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Toggle Add New Waiter Form Button
                    if (!_isAdding)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          // Auto generate ID e.g. W004
                          _idController.text = 'W00${waitersList.length + 1}';
                          setState(() => _isAdding = true);
                        },
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: const Text(
                          'REGISTER NEW WAITER',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1B26)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Register New Floor Waiter',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      setState(() => _isAdding = false),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                hintText: 'e.g. Sameer Verma',
                                isDense: true,
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _idController,
                                    decoration: InputDecoration(
                                      labelText: 'Waiter ID',
                                      hintText: 'e.g. W004',
                                      isDense: true,
                                      prefixIcon: const Icon(Icons.tag_rounded),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _pinController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Login PIN',
                                      hintText: '1234',
                                      isDense: true,
                                      prefixIcon: const Icon(
                                        Icons.pin_outlined,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Phone Number (Optional)',
                                hintText: '+91 98765 43210',
                                isDense: true,
                                prefixIcon: const Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _isLoading
                                  ? null
                                  : _handleCreateWaiter,
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'SAVE WAITER',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 20),
                    const Text(
                      'Active Floor Waiters:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (waitersList.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text('No waiters registered yet.'),
                        ),
                      )
                    else
                      ...waitersList.map((waiter) {
                        final waiterAssignedTables = allTables.where((t) {
                          if (t.assignedWaiterId.isNotEmpty &&
                              t.assignedWaiterId == waiter.waiterId) {
                            return true;
                          }
                          if (t.waiterName.isNotEmpty) {
                            if (t.waiterName == waiter.waiterId ||
                                t.waiterName == waiter.name) {
                              return true;
                            }
                            if (t.waiterName.contains(waiter.waiterId) ||
                                t.waiterName.toLowerCase().contains(
                                  waiter.name.toLowerCase(),
                                )) {
                              return true;
                            }
                          }
                          return false;
                        }).toList();

                        final int activeCount = waiterAssignedTables.length;
                        final String tablesListStr =
                            waiterAssignedTables.isNotEmpty
                            ? ' (${waiterAssignedTables.map((t) => 'T-${t.tableNumber}').join(', ')})'
                            : '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E1B26)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.15,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  waiter.waiterId,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: theme.colorScheme.primary,
                                  ),
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
                              'PIN: ${waiter.passcode} • $activeCount Active Table${activeCount == 1 ? '' : 's'}$tablesListStr',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () => _handleDeleteWaiter(waiter),
                            ),
                          ),
                        );
                      }),
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
