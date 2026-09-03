import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_requests/presentation/service_request_providers.dart';

class TableSetupDialog extends ConsumerStatefulWidget {
  final int currentTableCount;

  const TableSetupDialog({
    super.key,
    required this.currentTableCount,
  });

  static Future<void> show(BuildContext context, int currentCount) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => TableSetupDialog(currentTableCount: currentCount),
    );
  }

  @override
  ConsumerState<TableSetupDialog> createState() => _TableSetupDialogState();
}

class _TableSetupDialogState extends ConsumerState<TableSetupDialog> {
  late TextEditingController _countController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _countController = TextEditingController(
      text: widget.currentTableCount > 0
          ? widget.currentTableCount.toString()
          : '20',
    );
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  void _setCount(int count) {
    setState(() {
      _countController.text = count.toString();
    });
  }

  Future<void> _handleSave() async {
    final count = int.tryParse(_countController.text.trim());
    if (count == null || count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid table count (minimum 1).'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    if (count > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 100 tables supported per restaurant floor.'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      await repo.batchConfigureTables(count);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Successfully configured $count Restaurant Tables!'),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error configuring tables: $e'),
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

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.table_restaurant_rounded,
              color: theme.colorScheme.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configure Tables',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Set total tables for your restaurant',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 20),
            const Text(
              'Enter Total Number of Tables:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 10),

            // Number Input Row with Stepper Buttons
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: () {
                    final c = int.tryParse(_countController.text) ?? 1;
                    if (c > 1) _setCount(c - 1);
                  },
                  icon: const Icon(Icons.remove_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _countController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      hintText: 'e.g. 20',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: () {
                    final c = int.tryParse(_countController.text) ?? 0;
                    if (c < 100) _setCount(c + 1);
                  },
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick Preset Chips
            const Text(
              'Quick Presets:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [10, 15, 20, 30, 50].map((countValue) {
                final isSelected = _countController.text == countValue.toString();
                return ChoiceChip(
                  label: Text('$countValue Tables'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) _setCount(countValue);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Existing waiter assignments and table statuses will be preserved automatically.',
                      style: TextStyle(fontSize: 11.5, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _isLoading ? null : _handleSave,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'SAVE CONFIGURATION',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}
