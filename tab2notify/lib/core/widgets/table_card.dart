import 'package:flutter/material.dart';
import '../../features/service_requests/domain/table_model.dart';

class TableCard extends StatelessWidget {
  final TableModel table;
  final bool isManagerView;
  final VoidCallback? onUnlock;

  const TableCard({
    super.key,
    required this.table,
    this.isManagerView = false,
    this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isPending = table.isPending;
    final isAccepted = table.isAccepted;
    final isUnlocked = table.isUnlocked;

    // Card Colors based on state and authorization
    Color cardBg;
    Color borderColor;
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isManagerView && !isUnlocked) {
      // 🔒 LOCKED STATE (Manager authorization required)
      cardBg = theme.colorScheme.surface;
      borderColor = const Color(0xFFEA580C).withValues(alpha: 0.6);
      statusColor = const Color(0xFFEA580C);
      statusLabel = 'LOCKED';
      statusIcon = Icons.lock_outline_rounded;
    } else if (isPending) {
      // 🔴 RED STATE (Customer Requested Assistance)
      cardBg = theme.colorScheme.surface;
      borderColor = const Color(0xFFE53935);
      statusColor = const Color(0xFFE53935);
      statusLabel = 'PENDING';
      statusIcon = Icons.notifications_active_rounded;
    } else if (isAccepted) {
      // 🟢 PREVIOUS GREEN STATE (Accepted)
      cardBg = theme.colorScheme.surface;
      borderColor = const Color.fromARGB(255, 40, 150, 45);
      statusColor = const Color.fromARGB(255, 28, 175, 36);
      statusLabel = 'ACCEPTED';
      statusIcon = Icons.check_circle_rounded;
    } else {
      // 🟠 IDLE STATE (Orange Icon & Light Orange Border)
      cardBg = theme.colorScheme.surface;
      borderColor = const Color(0xFFFFB74D).withValues(alpha: 0.5);
      statusColor = const Color(0xFFFF9800);
      statusLabel = 'IDLE';
      statusIcon = Icons.radio_button_unchecked_rounded;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: isPending ? 2.0 : (isAccepted ? 1.8 : 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(
              alpha: isPending ? 0.35 : (isAccepted ? 0.25 : 0.08),
            ),
            blurRadius: isPending || isAccepted ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Top Left: Auth Status Dot / Badge in Manager View
          if (isManagerView)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isUnlocked
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
                      : const Color(0xFFEA580C).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                      size: 9,
                      color: isUnlocked
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFEA580C),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      isUnlocked ? 'UNLOCKED' : 'LOCKED',
                      style: TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.bold,
                        color: isUnlocked
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFEA580C),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Online Status Dot (Top Right Corner)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: table.isDeviceOnline
                    ? const Color.fromARGB(255, 25, 202, 34)
                    : const Color(0xFFE53935),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? Colors.black45 : Colors.white,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (table.isDeviceOnline
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE53935))
                        .withValues(alpha: 0.8),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),

          // Card Content (Centered, Fitted to prevent any overflow)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 6.0,
                vertical: 8.0,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Table Icon
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        (isManagerView && !isUnlocked)
                            ? Icons.lock_clock_rounded
                            : Icons.table_restaurant_rounded,
                        color: isDark && isAccepted
                            ? const Color(0xFF81C784)
                            : statusColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 5),

                    // Table Title
                    Text(
                      'Table ${table.tableNumber}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark
                            ? Colors.white
                            : (isAccepted ? const Color(0xFF1B5E20) : null),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),

                    // Status Badge or Unlock Button
                    if (isManagerView && !isUnlocked) ...[
                      // Manager Unlock Action Button
                      InkWell(
                        onTap: onUnlock,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEA580C), Color(0xFFFB923C)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEA580C).withValues(alpha: 0.35),
                                blurRadius: 4,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_open_rounded, color: Colors.white, size: 10.5),
                              SizedBox(width: 3.5),
                              Text(
                                'Unlock',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // Normal Operational Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: isAccepted
                              ? const Color(0xFF2E7D32)
                              : (isPending
                                  ? const Color(0xFFE53935)
                                  : statusColor.withValues(alpha: 0.15)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              statusIcon,
                              color: (isAccepted || isPending)
                                  ? Colors.white
                                  : statusColor,
                              size: 10,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: (isAccepted || isPending)
                                    ? Colors.white
                                    : statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),

                    // Assigned Waiter Pill
                    if (table.isAssigned)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_rounded,
                              size: 9,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              table.waiterName.split(' ').first,
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
