import 'package:flutter/material.dart';
import '../../features/service_requests/domain/table_model.dart';

class TableCard extends StatelessWidget {
  final TableModel table;
  final VoidCallback onTap;

  const TableCard({
    super.key,
    required this.table,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isPending = table.isPending;
    final isAccepted = table.isAccepted;

    // Card Colors based on state
    Color cardBg;
    Color borderColor;
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isPending) {
      // 🔴 RED STATE (Customer Requested Assistance)
      cardBg = isDark ? const Color(0xFF3B1115) : const Color(0xFFFFEBEE);
      borderColor = const Color(0xFFE53935);
      statusColor = const Color(0xFFE53935);
      statusLabel = 'PENDING';
      statusIcon = Icons.notifications_active_rounded;
    } else if (isAccepted) {
      // 🟢 GREEN STATE (Accepted)
      cardBg = isDark ? const Color(0xFF0F3318) : const Color(0xFFE8F5E9);
      borderColor = const Color(0xFF2E7D32);
      statusColor = const Color(0xFF2E7D32);
      statusLabel = 'ACCEPTED';
      statusIcon = Icons.check_circle_rounded;
    } else {
      // 🟠 IDLE STATE (Orange Icon & Light Orange Border)
      cardBg = theme.colorScheme.surface;
      borderColor = const Color(0xFFFFB74D).withValues(alpha: 0.5); // Light orange border
      statusColor = const Color(0xFFFF9800); // 🟠 Orange table icon for Idle state
      statusLabel = 'IDLE';
      statusIcon = Icons.radio_button_unchecked_rounded;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: isPending ? 2.0 : (isAccepted ? 1.8 : 1.0),
          ),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: isPending ? 0.35 : (isAccepted ? 0.2 : 0.04)),
              blurRadius: isPending ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Online Status Dot (Top Right Corner)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: table.isDeviceOnline ? const Color(0xFF00E676) : const Color(0xFFE53935),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (table.isDeviceOnline ? const Color(0xFF00E676) : const Color(0xFFE53935))
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
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Table Icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.table_restaurant_rounded,
                          color: statusColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Table Title
                      Text(
                        'Table ${table.tableNumber}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),

                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, color: statusColor, size: 10),
                            const SizedBox(width: 3),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 9.5,
                              ),
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
      ),
    );
  }
}
