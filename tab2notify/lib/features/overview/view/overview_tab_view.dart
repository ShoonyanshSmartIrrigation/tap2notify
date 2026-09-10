import 'dart:math' as math;
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

    final totalCount = tables.length;
    final pendingCount = pendingList.length;
    final acceptedCount = acceptedList.length;
    final idleCount = idleList.length;

    final pendingPercent = totalCount > 0 ? (pendingCount / totalCount) * 100 : 0.0;
    final acceptedPercent = totalCount > 0 ? (acceptedCount / totalCount) * 100 : 0.0;
    final idlePercent = totalCount > 0 ? (idleCount / totalCount) * 100 : 0.0;

    final List<DonutSliceData> chartSlices = [
      if (pendingCount > 0)
        DonutSliceData(
          label: 'Pending',
          value: pendingCount.toDouble(),
          displayValue: '$pendingCount',
          color: const Color(0xFFE53935),
        ),
      if (acceptedCount > 0)
        DonutSliceData(
          label: 'Accepted',
          value: acceptedCount.toDouble(),
          displayValue: '$acceptedCount',
          color: const Color(0xFF2E7D32),
        ),
      if (idleCount > 0)
        DonutSliceData(
          label: 'Idle',
          value: idleCount.toDouble(),
          displayValue: '$idleCount',
          color: const Color(0xFFFF9800),
        ),
    ];

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
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.5,
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

          const SizedBox(height: 16),

          // Modern Donut / Pie Chart Request Status Card
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
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF97316).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.pie_chart_rounded,
                            color: Color(0xFFF97316),
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Request Status Distribution',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pendingCount > 0
                            ? const Color(0xFFE53935).withValues(alpha: 0.15)
                            : const Color(0xFF2E7D32).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        pendingCount > 0 ? '$pendingCount Alert' : 'Normal',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: pendingCount > 0
                              ? const Color(0xFFE53935)
                              : const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Donut Chart & Left Legend Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left Legend List (matching reference image style)
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLegendRow(
                            color: const Color(0xFFE53935),
                            label: 'Pending',
                            count: pendingCount,
                            percent: pendingPercent,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),
                          _buildLegendRow(
                            color: const Color(0xFF2E7D32),
                            label: 'In Service',
                            count: acceptedCount,
                            percent: acceptedPercent,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),
                          _buildLegendRow(
                            color: const Color(0xFFFF9800),
                            label: 'Idle / Ready',
                            count: idleCount,
                            percent: idlePercent,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Donut Chart with Center Summary (matching reference image style)
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: SizedBox(
                          width: 165,
                          height: 165,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(165, 165),
                                painter: DonutChartPainter(
                                  slices: chartSlices,
                                  isDark: isDark,
                                ),
                              ),
                              // Center Total Ring Content
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$totalCount',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                                    ),
                                  ),
                                  Text(
                                    'TABLES',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
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
          ),
        ],
      ),
    );
  }

  Widget _buildLegendRow({
    required Color color,
    required String label,
    required int count,
    required double percent,
    required bool isDark,
  }) {
    return Row(
      children: [
        // Colored Dot (matching image style)
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '$count tables (${percent.toInt()}%)',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
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
}

class DonutSliceData {
  final String label;
  final double value;
  final String displayValue;
  final Color color;

  DonutSliceData({
    required this.label,
    required this.value,
    required this.displayValue,
    required this.color,
  });
}

class DonutChartPainter extends CustomPainter {
  final List<DonutSliceData> slices;
  final bool isDark;

  DonutChartPainter({
    required this.slices,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double total = slices.fold(0.0, (sum, s) => sum + s.value);
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.20;
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (total == 0) {
      final placeholderPaint = Paint()
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawCircle(center, radius, placeholderPaint);
      return;
    }

    double startAngle = -math.pi / 2; // Start from top
    const double gapAngle = 0.03; // Sleek slice gap

    for (final slice in slices) {
      final sweepAngle = (slice.value / total) * 2 * math.pi;
      final effectiveSweep = slices.length > 1
          ? math.max(0.0, sweepAngle - gapAngle)
          : sweepAngle;

      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle, effectiveSweep, false, paint);

      // Draw value on slice if slice is large enough
      if (sweepAngle > 0.45) {
        final midAngle = startAngle + (effectiveSweep / 2);
        final labelRadius = radius;
        final labelOffset = Offset(
          center.dx + labelRadius * math.cos(midAngle),
          center.dy + labelRadius * math.sin(midAngle),
        );

        final textSpan = TextSpan(
          text: slice.displayValue,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          Offset(
            labelOffset.dx - (textPainter.width / 2),
            labelOffset.dy - (textPainter.height / 2),
          ),
        );
      }

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant DonutChartPainter oldDelegate) {
    return oldDelegate.slices != slices || oldDelegate.isDark != isDark;
  }
}
