import 'package:flutter/material.dart';
import '../../features/service_requests/domain/table_model.dart';

class TableCard extends StatelessWidget {
  final TableModel table;
  final bool isManagerView;
  final VoidCallback? onUnlock;
  final VoidCallback? onTap;

  const TableCard({
    super.key,
    required this.table,
    this.isManagerView = false,
    this.onUnlock,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isPending = table.isPending;
    final isAccepted = table.isAccepted;
    final isUnlocked = table.isUnlocked;

    // Card Colors & Typography Tokens based on state and authorization
    Color cardBg;
    Color borderColor;
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isManagerView && !isUnlocked) {
      // 🔒 LOCKED STATE (Manager authorization required)
      cardBg = isDark ? const Color(0xFF1E1714) : const Color(0xFFFFF7ED);
      borderColor = const Color(0xFFEA580C).withValues(alpha: 0.55);
      statusColor = const Color(0xFFEA580C);
      statusLabel = 'LOCKED';
      statusIcon = Icons.lock_outline_rounded;
    } else if (isPending) {
      // 🔴 CALLING / PENDING STATE (Customer Requested Assistance)
      cardBg = isDark ? const Color(0xFF261517) : const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFEF4444);
      statusColor = const Color(0xFFEF4444);
      statusLabel = 'CALLING';
      statusIcon = Icons.notifications_active_rounded;
    } else if (isAccepted) {
      // 🟢 ACCEPTED / IN SERVICE STATE (Staff Attending)
      cardBg = isDark ? const Color(0xFF132219) : const Color(0xFFF0FDF4);
      borderColor = const Color(0xFF22C55E);
      statusColor = const Color(0xFF22C55E);
      statusLabel = 'ACCEPTED';
      statusIcon = Icons.check_circle_rounded;
    } else {
      // 🟠 IDLE / AVAILABLE STATE
      cardBg = isDark ? const Color(0xFF181818) : Colors.white;
      borderColor = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFE2E8F0);
      statusColor = const Color(0xFFF57C00);
      statusLabel = 'IDLE';
      statusIcon = Icons.radio_button_unchecked_rounded;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor,
              width: isPending ? 2.0 : (isAccepted ? 1.6 : 1.2),
            ),
            boxShadow: [
              BoxShadow(
                color: isPending
                    ? const Color(0xFFEF4444).withValues(alpha: 0.28)
                    : (isAccepted
                        ? const Color(0xFF22C55E).withValues(alpha: 0.20)
                        : (isDark
                            ? Colors.black.withValues(alpha: 0.35)
                            : Colors.black.withValues(alpha: 0.04))),
                blurRadius: isPending ? 14 : (isAccepted ? 10 : 6),
                offset: Offset(0, isPending ? 4 : 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Top Left: Auth Status Dot / Badge in Manager View
              if (isManagerView)
                Positioned(
                  top: 7,
                  left: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isUnlocked
                          ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                          : const Color(0xFFEA580C).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUnlocked
                              ? Icons.lock_open_rounded
                              : Icons.lock_rounded,
                          size: 9,
                          color: isUnlocked
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEA580C),
                        ),
                        const SizedBox(width: 2.5),
                        Text(
                          isUnlocked ? 'UNLOCKED' : 'LOCKED',
                          style: TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            color: isUnlocked
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFEA580C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Top Right: Online Status Beacon Dot
              Positioned(
                top: 8,
                right: 8,
                child: Tooltip(
                  message:
                      table.isDeviceOnline ? 'Device Online' : 'Device Offline',
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: table.isDeviceOnline
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF181818) : Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (table.isDeviceOnline
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFEF4444))
                              .withValues(alpha: 0.6),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Card Content (Centered and properly padded)
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Table Icon in Hero Squircle
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(
                            alpha: isDark ? 0.18 : 0.12,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            (isManagerView && !isUnlocked)
                                ? Icons.lock_clock_rounded
                                : (isPending
                                    ? Icons.notifications_active_rounded
                                    : (isAccepted
                                        ? Icons.room_service_rounded
                                        : Icons.table_restaurant_rounded)),
                            color: statusColor,
                            size: 19,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),

                      // Table Number Headline
                      Text(
                        'Table ${table.tableNumber}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          letterSpacing: -0.2,
                          color: isDark
                              ? Colors.white
                              : (isAccepted
                                  ? const Color(0xFF15803D)
                                  : (isPending
                                      ? const Color(0xFFB91C1C)
                                      : const Color(0xFF1E293B))),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),

                      // Status Badge or Unlock Action Button
                      if (isManagerView && !isUnlocked) ...[
                        InkWell(
                          onTap: onUnlock,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFEA580C), Color(0xFFFB923C)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFEA580C)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1.5),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_open_rounded,
                                  color: Colors.white,
                                  size: 10,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'Unlock',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: isPending
                                ? const Color(0xFFEF4444)
                                : (isAccepted
                                    ? const Color(0xFF22C55E)
                                    : statusColor.withValues(
                                        alpha: isDark ? 0.2 : 0.12,
                                      )),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                statusIcon,
                                color: (isAccepted || isPending)
                                    ? Colors.white
                                    : statusColor,
                                size: 9.5,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  color: (isAccepted || isPending)
                                      ? Colors.white
                                      : statusColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 9,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),

                      // Assigned Waiter Pill
                      if (table.isAssigned)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: isDark ? 0.15 : 0.08,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.25,
                              ),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 9,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 2.5),
                              Flexible(
                                child: Text(
                                  table.waiterName.split(' ').first,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
