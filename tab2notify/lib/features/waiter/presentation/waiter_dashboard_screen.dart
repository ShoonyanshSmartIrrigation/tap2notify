import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

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

  // =========================================================================
  // 1. DIALOG / BOTTOM SHEET: ACCEPT TABLE CALL (URGENT PENDING STATE)
  // =========================================================================
  void _showAcceptDialog(TableModel table, String waiterName, String waiterId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF181520) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE53935).withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            MediaQuery.of(bottomSheetContext).viewInsets.bottom + 26,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab Handle Bar
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Animated Service Bell Hero with Pulsing Aura
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE53935).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFFE53935).withValues(alpha: 0.35),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE53935).withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: RepaintBoundary(
                    child: Lottie.asset(
                      'assets/animations/service_bell.json',
                      fit: BoxFit.contain,
                      repeat: true,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.notifications_active_rounded,
                        color: Color(0xFFE53935),
                        size: 38,
                      ),
                    ),
                  ),
                ),
              ).animate().scale(duration: 350.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 14),

              // Title and Table Calling Number
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'ACTIVE CALL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Table ${table.tableNumber}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              Text(
                'Guest has pressed the service bell and is waiting for assistance.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),

              const SizedBox(height: 18),

              // Staff Details Info Tile
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryOrange.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.primaryOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assigned Waiter',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '$waiterName ($waiterId)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_rounded,
                            size: 12,
                            color: Color(0xFF2E7D32),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'ONLINE',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.grey[300]!,
                        ),
                      ),
                      onPressed: () {
                        _handledRequestId = null;
                        Navigator.pop(bottomSheetContext);
                      },
                      child: Text(
                        'DISMISS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF16A34A).withValues(alpha: 0.38),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () async {
                          _handledRequestId = null;
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(bottomSheetContext);

                          HapticFeedback.mediumImpact();
                          final repo = ref.read(
                            waiterServiceRequestRepositoryProvider,
                          );
                          await repo.acceptTableRequest(
                            tableId: table.id,
                            waiterName: waiterName,
                            waiterId: waiterId,
                          );

                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Table ${table.tableNumber} Request Accepted!',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF16A34A),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          }
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'ACCEPT CALL',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
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

  // =========================================================================
  // 2. DIALOG / BOTTOM SHEET: COMPLETE SERVICE (ACCEPTED IN-PROGRESS STATE)
  // =========================================================================
  void _showCompleteDialog(TableModel table) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF181520) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            MediaQuery.of(bottomSheetContext).viewInsets.bottom + 26,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab Handle Bar
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Animated Success Checkmark Hero
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: RepaintBoundary(
                    child: Lottie.asset(
                      'assets/animations/auth_success.json',
                      fit: BoxFit.contain,
                      repeat: false,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.check_circle_outline_rounded,
                        color: Color(0xFF2E7D32),
                        size: 38,
                      ),
                    ),
                  ),
                ),
              ).animate().scale(duration: 350.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 14),

              // Title and Table State
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'IN PROGRESS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Table ${table.tableNumber}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              Text(
                'Have you served the guest and completed their service request?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),

              const SizedBox(height: 22),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.grey[300]!,
                        ),
                      ),
                      onPressed: () {
                        _handledRequestId = null;
                        Navigator.pop(bottomSheetContext);
                      },
                      child: Text(
                        'KEEP ACTIVE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF15803D).withValues(alpha: 0.38),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () async {
                          _handledRequestId = null;
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(bottomSheetContext);

                          HapticFeedback.mediumImpact();
                          final repo = ref.read(
                            waiterServiceRequestRepositoryProvider,
                          );
                          await repo.resetTableStatus(table.id);

                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.task_alt_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Table ${table.tableNumber} Marked as Served & Ready!',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF16A34A),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          }
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.done_all_rounded, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'MARK AS SERVED',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
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

  // =========================================================================
  // 3. DIALOG / BOTTOM SHEET: IDLE TABLE DETAILS & SERVICE DISPATCH
  // =========================================================================
  void _showIdleDialog(TableModel table, String waiterName, String waiterId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF181520) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            MediaQuery.of(bottomSheetContext).viewInsets.bottom + 26,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab Handle Bar
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Amber Icon Hero
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.table_restaurant_rounded,
                  color: Color(0xFFFF9800),
                  size: 34,
                ),
              ).animate().scale(duration: 350.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 14),

              // Title and Table State
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'IDLE & READY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Table ${table.tableNumber}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              Text(
                'Assigned Staff: $waiterName ($waiterId)\nNo active service requested. Table is ready for dining.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),

              const SizedBox(height: 22),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.grey[300]!,
                        ),
                      ),
                      onPressed: () => Navigator.pop(bottomSheetContext),
                      child: Text(
                        'CLOSE',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFDC2626).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(bottomSheetContext);

                          HapticFeedback.mediumImpact();
                          final repo = ref.read(
                            waiterServiceRequestRepositoryProvider,
                          );
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
                                backgroundColor: const Color(0xFFDC2626),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.notifications_active_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'CALL SERVICE',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
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

  // =========================================================================
  // 4. DIALOG / BOTTOM SHEET: GATEWAY TELEMETRY DIAGNOSTICS
  // =========================================================================
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF181520) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            MediaQuery.of(ctx).viewInsets.bottom + 26,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
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
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFE53935))
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isConnected
                              ? Icons.wifi_rounded
                              : Icons.wifi_find_rounded,
                          color: isConnected
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFE53935),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Gateway Telemetry',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            isConnected
                                ? 'Local Wi-Fi Mesh Connected'
                                : 'Searching Local Subnet...',
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
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Gateway Status',
                    onPressed: () {
                      HapticFeedback.lightImpact();
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
                isConnected
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFF57C00),
              ),
              _buildDiagRow(
                'Gateway IP Address',
                gatewayIp.isNotEmpty ? '$gatewayIp:80' : 'Auto-discovery',
                isDark ? Colors.white70 : Colors.black87,
              ),
              _buildDiagRow(
                'Hardware Device State',
                '${tables.where((t) => t.isDeviceOnline).length} / ${tables.length} Devices Online',
                isDark ? Colors.white : Colors.black87,
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      color: AppColors.primaryOrange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ESP32 Gateway communicates with instant sub-5ms low latency event dispatching.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiagRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7.0),
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
                fontWeight: FontWeight.w800,
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

  // =========================================================================
  // MAIN BUILD METHOD
  // =========================================================================
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
              RepaintBoundary(
                child: Lottie.asset(
                  'assets/animations/auth_loading.json',
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Loading Staff Session...',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
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
          isDark ? const Color(0xFF0F0E13) : const Color(0xFFF8FAFC),
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
        toolbarHeight: 68,
        backgroundColor: isDark ? const Color(0xFF16141E) : Colors.white,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Builder(
          builder: (drawerCtx) => InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.lightImpact();
              Scaffold.of(drawerCtx).openDrawer();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  // Avatar Profile with Online Ring
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFEA580C,
                              ).withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            waiterName.isNotEmpty
                                ? waiterName.substring(0, 1).toUpperCase()
                                : 'W',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      // Online Duty Indicator
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF16141E)
                                  : Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Waiter Name & Status Pill
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
                                  fontSize: 16.5,
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
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryOrange.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ID: $waiterId',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primaryOrange,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${assignedTables.length} Tables',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
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
          // Wi-Fi Telemetry Live Pill
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
                  color: (isConnected
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (isConnected
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444))
                        .withValues(alpha: 0.35),
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
                    const SizedBox(width: 5),
                    Text(
                      isConnected ? 'MESH ON' : 'SEARCH',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
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
            // 1. Hero Floor Status Card (Command Center)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: _buildHeroCommandBanner(
                  theme: theme,
                  isDark: isDark,
                  pendingCount: pendingTables.length,
                  totalCount: assignedTables.length,
                ),
              ),
            ),

            // 2. Modern Segmented Filter Pills
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 6.0,
                ),
                child: Row(
                  children: [
                    _buildFilterPill(
                      value: 'all',
                      label: 'All Tables',
                      count: assignedTables.length,
                      accentColor: AppColors.primaryOrange,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      value: 'pending',
                      label: 'Urgent Calls',
                      count: pendingTables.length,
                      accentColor: const Color(0xFFEF4444),
                      isDark: isDark,
                      isUrgent: pendingTables.isNotEmpty,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      value: 'accepted',
                      label: 'In Service',
                      count: acceptedTables.length,
                      accentColor: const Color(0xFF22C55E),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      value: 'idle',
                      label: 'Idle / Ready',
                      count: idleTables.length,
                      accentColor: const Color(0xFFF59E0B),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),

            // 3. Table Grid or Empty State
            if (displayList.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 40.0,
                    horizontal: 24.0,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RepaintBoundary(
                          child: Lottie.asset(
                            'assets/animations/restaurant_service.json',
                            width: 140,
                            height: 140,
                            repeat: true,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.table_restaurant_outlined,
                              size: 64,
                              color: AppColors.primaryOrange,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          assignedTables.isEmpty
                              ? 'No Tables Assigned Yet'
                              : 'No Tables in This Filter',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          assignedTables.isEmpty
                              ? 'Please ask your restaurant Floor Manager to allocate tables to your ID ($waiterId).'
                              : 'Try selecting a different filter category to see your other floor tables.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        if (_selectedFilter != 'all') ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(
                              Icons.filter_alt_off_rounded,
                              size: 16,
                            ),
                            label: const Text('Show All Tables'),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              setState(() => _selectedFilter = 'all');
                            },
                          ),
                        ],
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
                    childAspectRatio: 0.74,
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

  // =========================================================================
  // HERO COMMAND BANNER COMPONENT
  // =========================================================================
  Widget _buildHeroCommandBanner({
    required ThemeData theme,
    required bool isDark,
    required int pendingCount,
    required int totalCount,
  }) {
    final hasPending = pendingCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: hasPending
            ? () {
                HapticFeedback.lightImpact();
                setState(() => _selectedFilter = 'pending');
              }
            : null,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: hasPending
                  ? (isDark
                      ? [const Color(0xFF3B1212), const Color(0xFF260D0D)]
                      : [const Color(0xFFFEE2E2), const Color(0xFFFECACA)])
                  : (isDark
                      ? [const Color(0xFF17201D), const Color(0xFF101715)]
                      : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)]),
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: hasPending
                  ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                  : const Color(0xFF10B981).withValues(alpha: 0.35),
              width: hasPending ? 1.8 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: hasPending
                    ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: hasPending ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Hero Icon / Lottie Indicator
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasPending
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                  boxShadow: [
                    BoxShadow(
                      color: hasPending
                          ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                          : const Color(0xFF10B981).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    hasPending
                        ? Icons.notifications_active_rounded
                        : Icons.task_alt_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Title and Descriptive Metrics
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            hasPending
                                ? '$pendingCount Table(s) Calling!'
                                : 'Floor Operations Normal',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: hasPending
                                  ? (isDark
                                      ? const Color(0xFFFCA5A5)
                                      : const Color(0xFF991B1B))
                                  : (isDark
                                      ? const Color(0xFF6EE7B7)
                                      : const Color(0xFF065F46)),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasPending
                          ? 'Guests requesting service • Tap to attend'
                          : '$totalCount table(s) under your care • All attended',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: hasPending
                            ? (isDark
                                ? const Color(0xFFF87171)
                                : const Color(0xFFB91C1C))
                            : (isDark
                                ? const Color(0xFFA7F3D0)
                                : const Color(0xFF047857)),
                      ),
                    ),
                  ],
                ),
              ),

              if (hasPending)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VIEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white,
                        size: 10,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // FILTER PILL COMPONENT
  // =========================================================================
  Widget _buildFilterPill({
    required String value,
    required String label,
    required int count,
    required Color accentColor,
    required bool isDark,
    bool isUrgent = false,
  }) {
    final isSelected = _selectedFilter == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _selectedFilter = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor
                : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : (isUrgent
                      ? const Color(0xFFEF4444).withValues(alpha: 0.45)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0))),
              width: isUrgent && !isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
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
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : (isUrgent
                          ? const Color(0xFFEF4444)
                          : accentColor.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: isSelected
                        ? Colors.white
                        : (isUrgent ? Colors.white : accentColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // DRAWER NAVIGATION
  // =========================================================================
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
          isDark ? const Color(0xFF141218) : const Color(0xFFFBFBFB),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. Drawer Header Profile Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF261D1A), const Color(0xFF1E1B26)]
                      : [const Color(0xFFFFF3E0), Colors.white],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Avatar Circle
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFEA580C,
                          ).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 26,
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
                            fontWeight: FontWeight.bold,
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
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ID: $waiterId',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
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
                                color: const Color(
                                  0xFF2E7D32,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: Color(0xFF2E7D32),
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'On Duty',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2E7D32),
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

            const SizedBox(height: 14),

            // 2. Floor Status Box
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'FLOOR OVERVIEW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDrawerStatTile(
                          title: 'Pending Calls',
                          count: pendingTables.length,
                          color: const Color(0xFFE53935),
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
                          title: 'In Service',
                          count: acceptedTables.length,
                          color: const Color(0xFF2E7D32),
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
                          color: const Color(0xFFFF9800),
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
            const SizedBox(height: 14),

            // 3. Quick Actions / Preferences
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'PREFERENCES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isDark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: const Text(
                      'Dark Mode',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Switch.adaptive(
                      value: isDark,
                      activeTrackColor: theme.colorScheme.primary,
                      onChanged: (_) {
                        ref.read(themeModeProvider.notifier).toggleTheme();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 4. Wi-Fi Gateway Telemetry Box
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'GATEWAY TELEMETRY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1B26) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              (isConnected
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFE53935))
                                  .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isConnected
                              ? Icons.wifi_rounded
                              : Icons.wifi_find_rounded,
                          size: 18,
                          color: isConnected
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFE53935),
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
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              gatewayIp.isNotEmpty
                                  ? 'IP: $gatewayIp:80'
                                  : 'Auto-discovery active',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.analytics_outlined, size: 16),
                      label: const Text(
                        'Open Diagnostics',
                        style: TextStyle(fontSize: 12),
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
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(context);
                _handleSignOut();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFE53935).withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFE53935),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.bold,
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
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
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
                    fontSize: 15,
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
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
