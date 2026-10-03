import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
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
      barrierDismissible: true,
      builder: (ctx) => TableSetupDialog(currentTableCount: currentCount),
    );
  }

  @override
  ConsumerState<TableSetupDialog> createState() => _TableSetupDialogState();
}

class _TableSetupDialogState extends ConsumerState<TableSetupDialog> {
  late TextEditingController _countController;
  bool _isLoading = false;

  final List<int> _presetOptions = const [10, 15, 20, 30, 50, 75];

  @override
  void initState() {
    super.initState();
    _countController = TextEditingController(
      text: widget.currentTableCount > 0
          ? widget.currentTableCount.toString()
          : '20',
    );
    _countController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  int get _currentCount => int.tryParse(_countController.text.trim()) ?? 0;

  void _setCount(int count) {
    setState(() {
      _countController.text = count.toString();
      _countController.selection = TextSelection.fromPosition(
        TextPosition(offset: _countController.text.length),
      );
    });
  }

  void _increment() {
    final c = _currentCount;
    if (c < 100) {
      _setCount(c + 1);
    }
  }

  void _decrement() {
    final c = _currentCount;
    if (c > 1) {
      _setCount(c - 1);
    }
  }

  Future<void> _handleSave() async {
    final count = int.tryParse(_countController.text.trim());
    if (count == null || count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid table count (minimum 1).'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (count > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 100 tables supported per restaurant floor.'),
          backgroundColor: AppColors.error,
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
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Successfully configured $count Restaurant Tables!',
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
            content: Text('Error configuring tables: $e'),
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

    final currentVal = _currentCount;
    final canDecrement = currentVal > 1;
    final canIncrement = currentVal < 100;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1B26) : Colors.white,
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header Bar
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Gradient Icon Badge
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
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.table_restaurant_rounded,
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
                          'Configure Tables',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Set total tables for floor layout',
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
                      onTap: _isLoading ? null : () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04),
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

              const SizedBox(height: 18),

              // Currently Active Summary Pill
              if (widget.currentTableCount > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF282433)
                        : const Color(0xFFF4F6F8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.layers_rounded,
                        size: 16,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Currently Active:',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.7)
                              : AppColors.lightSecondaryText,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${widget.currentTableCount} Tables',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Hero Counter Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF17151D)
                      : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : primaryColor.withValues(alpha: 0.2),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'TOTAL NUMBER OF TABLES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.5)
                            : AppColors.lightSecondaryText,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Interactive Stepper Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Decrement Button
                        Material(
                          color: canDecrement
                              ? (isDark
                                  ? const Color(0xFF2B2738)
                                  : Colors.white)
                              : (isDark
                                  ? const Color(0xFF1E1B26)
                                  : const Color(0xFFEDEDED)),
                          borderRadius: BorderRadius.circular(16),
                          elevation: canDecrement ? 1 : 0,
                          shadowColor: Colors.black26,
                          child: InkWell(
                            onTap: canDecrement ? _decrement : null,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: canDecrement
                                      ? (isDark
                                          ? Colors.white.withValues(alpha: 0.12)
                                          : Colors.black.withValues(alpha: 0.1))
                                      : Colors.transparent,
                                ),
                              ),
                              child: Icon(
                                Icons.remove_rounded,
                                size: 22,
                                color: canDecrement
                                    ? primaryColor
                                    : (isDark ? Colors.white24 : Colors.black26),
                              ),
                            ),
                          ),
                        ),

                        // Editable Big Number Field
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: _countController,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    color: primaryColor,
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    border: InputBorder.none,
                                    hintText: '0',
                                  ),
                                ),
                                Text(
                                  'Tables',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.6)
                                        : AppColors.lightSecondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Increment Button
                        Material(
                          color: canIncrement
                              ? (isDark
                                  ? const Color(0xFF2B2738)
                                  : Colors.white)
                              : (isDark
                                  ? const Color(0xFF1E1B26)
                                  : const Color(0xFFEDEDED)),
                          borderRadius: BorderRadius.circular(16),
                          elevation: canIncrement ? 1 : 0,
                          shadowColor: Colors.black26,
                          child: InkWell(
                            onTap: canIncrement ? _increment : null,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: canIncrement
                                      ? (isDark
                                          ? Colors.white.withValues(alpha: 0.12)
                                          : Colors.black.withValues(alpha: 0.1))
                                      : Colors.transparent,
                                ),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                size: 22,
                                color: canIncrement
                                    ? primaryColor
                                    : (isDark ? Colors.white24 : Colors.black26),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Text(
                      'Min: 1 table  •  Max: 100 tables',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Quick Presets Header
              Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 15,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'QUICK PRESETS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : AppColors.lightSecondaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Presets Grid / Wrap
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presetOptions.map((countValue) {
                  final isSelected = currentVal == countValue;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _setCount(countValue),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryColor
                              : (isDark
                                  ? const Color(0xFF282433)
                                  : const Color(0xFFF1F3F5)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? primaryColor
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06)),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '$countValue Tables',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.85)
                                        : AppColors.lightText),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Reassurance / Info Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 17,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Waiter assignments & active table requests remain safely preserved.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.85)
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // Action Buttons Row
              Row(
                children: [
                  // Cancel Button
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.15),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Save Button
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFB923C),
                            Color(0xFFEA580C),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEA580C).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isLoading ? null : _handleSave,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_rounded, size: 18, color: Colors.white),
                                        SizedBox(width: 6),
                                        Text(
                                          'Save Setup',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
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
        ),
      ),
    );
  }
}
