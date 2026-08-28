import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../features/service_requests/domain/service_request_model.dart';

class RequestCard extends StatelessWidget {
  final ServiceRequestModel request;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onComplete;
  final VoidCallback onTap;

  const RequestCard({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onReject,
    required this.onComplete,
    required this.onTap,
  });

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  Color _getStatusColor() {
    switch (request.status) {
      case 'pending':
        return const Color(0xFFE53935); // Vivid RED (Matches ESP32 Red LED)
      case 'accepted':
        return const Color(0xFF2E7D32); // Vivid GREEN (Matches ESP32 Green LED)
      case 'completed':
        return const Color(0xFF1E88E5); // Blue
      case 'rejected':
        return const Color(0xFF757575); // Grey
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _getStatusColor();
    final isPending = request.status == 'pending';
    final isAccepted = request.status == 'accepted';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isPending
              ? (isDark ? const Color(0xFF261214) : const Color(0xFFFFEBEE))
              : isAccepted
                  ? (isDark ? const Color(0xFF112415) : const Color(0xFFE8F5E9))
                  : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: statusColor.withValues(alpha: isPending || isAccepted ? 0.8 : 0.2),
            width: isPending || isAccepted ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: isPending ? 0.25 : (isAccepted ? 0.2 : 0.05)),
              blurRadius: isPending || isAccepted ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Badge & Time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPending
                              ? Icons.notifications_active_rounded
                              : isAccepted
                                  ? Icons.check_circle_rounded
                                  : request.status == 'completed'
                                      ? Icons.task_alt
                                      : Icons.cancel_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPending
                              ? '🔴 PENDING (RED LED)'
                              : isAccepted
                                  ? '🟢 ACCEPTED (GREEN LED)'
                                  : request.status.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatTime(request.createdAt),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Room & Table Details
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Room ${request.roomNumber}',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Table ${request.tableNumber}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          request.requestType.toLowerCase() == 'water'
                              ? 'Guest requested Water Service'
                              : 'Guest requested Assistance',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        request.requestType.toLowerCase() == 'water' ? '💧' : '🔔',
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  ),
                ],
              ),

              // Action Buttons
              if (isPending) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD32F2F),
                          side: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: onAccept,
                        icon: const Icon(Icons.check_circle, size: 20),
                        label: const Text('ACCEPT REQUEST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (isAccepted) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.task_alt, size: 20),
                    label: const Text('MARK COMPLETED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
