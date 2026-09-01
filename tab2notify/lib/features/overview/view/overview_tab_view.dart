import 'package:flutter/material.dart';
import '../../service_requests/domain/table_model.dart';

class OverviewTabView extends StatelessWidget {
  final List<TableModel> tables;
  final ValueChanged<int> onSelectTab;

  const OverviewTabView({
    super.key,
    required this.tables,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final pendingList = tables.where((t) => t.isPending).toList();
    final acceptedList = tables.where((t) => t.isAccepted).toList();
    final idleList = tables.where((t) => !t.isPending && !t.isAccepted).toList();

    final totalCount = tables.isNotEmpty ? tables.length : 6;
    final pendingCount = pendingList.length;
    final acceptedCount = acceptedList.length;
    final idleCount = tables.isNotEmpty ? idleList.length : 6;

    final pendingPercent = totalCount > 0 ? (pendingCount / totalCount) : 0.0;
    final acceptedPercent = totalCount > 0 ? (acceptedCount / totalCount) : 0.0;
    final idlePercent = totalCount > 0 ? (idleCount / totalCount) : 1.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Banner
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Table Overview',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Live hospitality metrics & service analytics',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.2)
                      : const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.sync_rounded, color: Color(0xFF2E7D32), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'REALTIME',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 4 Modern KPI Cards Grid
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.35,
            children: [
              _buildKpiCard(
                title: 'Pending Alert',
                count: '$pendingCount',
                subtitle: pendingCount > 0 ? 'Requires Action' : 'All Clear',
                icon: Icons.notifications_active_rounded,
                color: const Color(0xFFE53935),
                isDark: isDark,
                onTap: () => onSelectTab(0),
              ),
              _buildKpiCard(
                title: 'In Service',
                count: '$acceptedCount',
                subtitle: 'Accepted Requests',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF2E7D32),
                isDark: isDark,
                onTap: () => onSelectTab(0),
              ),
              _buildKpiCard(
                title: 'Idle / Ready',
                count: '$idleCount',
                subtitle: 'Available Tables',
                icon: Icons.table_restaurant_rounded,
                color: const Color(0xFFFF9800),
                isDark: isDark,
                onTap: () => onSelectTab(0),
              ),
              _buildKpiCard(
                title: 'Total Tables',
                count: '$totalCount',
                subtitle: 'Connected Devices',
                icon: Icons.sensors_rounded,
                color: const Color(0xFF0284C7),
                isDark: isDark,
                onTap: () => onSelectTab(0),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Service Distribution Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF1E1B26),
                        const Color(0xFF14121A),
                      ]
                    : [
                        Colors.white,
                        const Color(0xFFF8FAFC),
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Live Table Capacity',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${((pendingCount + acceptedCount) / (totalCount > 0 ? totalCount : 1) * 100).toInt()}% Active',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: pendingCount > 0
                            ? const Color(0xFFE53935)
                            : const Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Multi-color Segmented Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 12,
                    child: Row(
                      children: [
                        if (pendingPercent > 0)
                          Expanded(
                            flex: (pendingPercent * 100).round(),
                            child: Container(color: const Color(0xFFE53935)),
                          ),
                        if (acceptedPercent > 0)
                          Expanded(
                            flex: (acceptedPercent * 100).round(),
                            child: Container(color: const Color(0xFF2E7D32)),
                          ),
                        if (idlePercent > 0)
                          Expanded(
                            flex: (idlePercent * 100).round(),
                            child: Container(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildLegendItem(
                      color: const Color(0xFFE53935),
                      label: 'Pending ($pendingCount)',
                      isDark: isDark,
                    ),
                    _buildLegendItem(
                      color: const Color(0xFF2E7D32),
                      label: 'In Service ($acceptedCount)',
                      isDark: isDark,
                    ),
                    _buildLegendItem(
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      label: 'Idle ($idleCount)',
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Speed & System Performance Metrics
          Text(
            'System Performance',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E1B26)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              children: [
                _buildMetricRow(
                  icon: Icons.bolt_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Average Response Time',
                  value: '< 12 sec',
                  status: 'Fast ⚡',
                  isDark: isDark,
                ),
                const Divider(height: 24),
                _buildMetricRow(
                  icon: Icons.bluetooth_audio_rounded,
                  iconColor: const Color(0xFF0284C7),
                  title: 'BLE Wireless Signal',
                  value: '-42 dBm',
                  status: 'Strong 📶',
                  isDark: isDark,
                ),
                const Divider(height: 24),
                _buildMetricRow(
                  icon: Icons.shield_rounded,
                  iconColor: const Color(0xFF2E7D32),
                  title: 'Hardware Link Status',
                  value: 'ESP32 Online',
                  status: 'Synced ✓',
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String count,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1E1B26)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.3 : 0.2),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isDark ? 0.15 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required bool isDark,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String status,
    required bool isDark,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
