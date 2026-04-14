import 'package:flutter/material.dart';

/// Modern widget to display current HR and HRV values
/// Inspired by Calm/Headspace design
class HrHrvDisplayNew extends StatelessWidget {
  final double hr;
  final double hrv;
  final List<HrDataPoint> hrHistory; // HR values for the last minute
  final bool isHrStable; // Indicates if HR measurement has 30+ seconds of data
  final String stressLevel;
  final bool isHrvStable; // New: indicates if HRV measurement is reliable
  final int?
      measurementDurationSeconds; // Timer for metrics requiring long measurement
  final String? activityLevel; // Activity level from accelerometer/gyroscope
  final String? activityDescription; // Human-readable activity description
  final bool showMonitoring; // Show monitoring indicator

  const HrHrvDisplayNew({
    super.key,
    required this.hr,
    required this.hrv,
    this.hrHistory = const [], // HR history for chart display
    this.isHrStable = false, // Default to false - require explicit stable state
    required this.stressLevel,
    this.isHrvStable = false, // Default to false - require explicit stable state
    this.measurementDurationSeconds,
    this.activityLevel,
    this.activityDescription,
    this.showMonitoring = false,
  });

  @override
  Widget build(BuildContext context) {
    // Stress level colors matching app theme:
    // - Relaxed: Teal (matches RMSSD/HRV - good variability = relaxed)
    // - Stressed: Red (matches HR - elevated heart rate = stress)
    final Map<String, Color> stressColors = {
      'relaxed': const Color(0xFF4ECDC4), // Teal - matches RMSSD color
      'stressed': const Color(0xFFFF6B6B), // Red - matches HR color
    };

    final Map<String, String> stressLabels = {
      'relaxed': 'Relaxed',
      'stressed': 'Stressed',
    };

    final Map<String, IconData> stressIcons = {
      'relaxed': Icons.spa_rounded, // Calm/relaxation icon
      'stressed': Icons.bolt_rounded, // Energy/alert icon
    };

    final stressColor = stressColors[stressLevel] ?? const Color(0xFF4ECDC4);
    final stressText = stressLabels[stressLevel] ?? 'Relaxed';
    final stressIcon = stressIcons[stressLevel] ?? Icons.spa_rounded;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        children: [
          // HR and RMSSD side by side
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.favorite,
                  iconColor: const Color(0xFFFF6B6B),
                  label: 'Heart Rate',
                  value: (measurementDurationSeconds == null || measurementDurationSeconds! < 30)
                      ? 'Loading...'
                      : (isHrStable 
                          ? '${hr.toStringAsFixed(0)} BPM'
                          : 'Measuring...'),
                  iconBackground: const Color(0xFFFFE5E5),
                  isLoading: measurementDurationSeconds == null || measurementDurationSeconds! < 30 || !isHrStable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  icon: Icons.show_chart,
                  iconColor: const Color(0xFF4ECDC4),
                  label: 'RMSSD',
                  value: (measurementDurationSeconds == null || measurementDurationSeconds! < 60)
                      ? 'Loading...'
                      : (hrv < 0
                          ? 'Loading...'
                          : (isHrvStable
                              ? '${hrv.toStringAsFixed(1)} ms'
                              : 'Measuring...')),
                  iconBackground: const Color(0xFFE0F7F6),
                  isLoading: measurementDurationSeconds == null || measurementDurationSeconds! < 60 || hrv < 0 || !isHrvStable,
                ),
              ),
            ],
          ),
          if (showMonitoring) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF4ECDC4).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF4ECDC4).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.monitor_heart,
                    size: 16,
                    color: const Color(0xFF4ECDC4),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Monitoring',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF4ECDC4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // HR History Chart below the metrics - only show after 30 seconds
          // and exclude data from the loading phase (first 30 seconds)
          if (hrHistory.isNotEmpty && 
              measurementDurationSeconds != null && 
              measurementDurationSeconds! >= 30 && 
              isHrStable) ...[
            const SizedBox(height: 12),
            _HrHistoryChart(
              hrHistory: hrHistory.where((point) {
                final cutoffTime = DateTime.now().subtract(
                  Duration(seconds: measurementDurationSeconds! - 30)
                );
                return point.timestamp.isAfter(cutoffTime);
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: stressColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  stressIcon,
                  color: stressColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  stressText,
                  style: TextStyle(
                    color: stressColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // Activity Level Indicator (if available)
          if (activityLevel != null && activityDescription != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.blueGrey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blueGrey[200]!, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getActivityIcon(activityLevel!),
                    color: Colors.blueGrey[700],
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      activityDescription!,
                      style: TextStyle(
                        color: Colors.blueGrey[800],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getActivityIcon(String level) {
    switch (level) {
      case 'resting':
        return Icons.airline_seat_individual_suite;
      case 'light':
        return Icons.directions_walk;
      case 'moderate':
        return Icons.directions_run;
      case 'vigorous':
        return Icons.fitness_center;
      case 'intense':
        return Icons.bolt;
      default:
        return Icons.help_outline;
    }
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String value;
  final bool isLoading; // New: shows loading indicator

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.value,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              isLoading
                  ? SizedBox(
                      height: 18,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(iconColor),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              value,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Data point for HR history
class HrDataPoint {
  final DateTime timestamp;
  final double hr;

  const HrDataPoint({required this.timestamp, required this.hr});
}

/// Widget to display HR history as a line chart
class _HrHistoryChart extends StatelessWidget {
  final List<HrDataPoint> hrHistory;

  const _HrHistoryChart({required this.hrHistory});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 240, // Doubled height for better visibility
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE5E5).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: CustomPaint(
            painter: _HrChartPainter(hrHistory: hrHistory),
            child: Container(),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Heart Rate',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Custom painter for HR history chart
class _HrChartPainter extends CustomPainter {
  final List<HrDataPoint> hrHistory;

  _HrChartPainter({required this.hrHistory});

  @override
  void paint(Canvas canvas, Size size) {
    if (hrHistory.length < 2) return;

    // Find min and max HR for scaling
    final hrValues = hrHistory.map((e) => e.hr).toList();
    final minHr = hrValues.reduce((a, b) => a < b ? a : b);
    final maxHr = hrValues.reduce((a, b) => a > b ? a : b);
    
    // Add padding to the range
    final hrRange = maxHr - minHr;
    final paddedMin = (minHr - hrRange * 0.1).floorToDouble();
    final paddedMax = (maxHr + hrRange * 0.1).ceilToDouble();
    final range = paddedMax - paddedMin;
    
    if (range == 0) return;

    // Dynamic time range: calculate actual data span
    final oldestPoint = hrHistory.first.timestamp;
    final newestPoint = hrHistory.last.timestamp;
    final dataSpanSeconds = newestPoint.difference(oldestPoint).inSeconds;
    
    // Determine time window to display (at least 1 minute, up to 5 minutes)
    final displaySeconds = dataSpanSeconds < 60 
        ? 60 // Show at least 1 minute window even if less data
        : (dataSpanSeconds > 300 ? 300 : dataSpanSeconds); // Cap at 5 minutes
    
    // Use newest data point as reference (not current time) to prevent leftward drift
    final startTime = newestPoint.subtract(Duration(seconds: displaySeconds));

    // Define chart area (leave space for labels)
    const double yAxisWidth = 28; // Space for y-axis labels on the left (reduced to maximize chart area)
    const double bottomMargin = 20; // Space for x-axis labels
    final chartWidth = size.width - yAxisWidth;
    final chartHeight = size.height - bottomMargin;

    // Text style for labels
    final textStyle = TextStyle(
      color: Colors.grey[600],
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    // Draw y-axis labels (min and max HR)
    final minHrText = TextPainter(
      text: TextSpan(text: '${paddedMin.toInt()}', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    
    final maxHrText = TextPainter(
      text: TextSpan(text: '${paddedMax.toInt()}', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    minHrText.paint(canvas, Offset(0, chartHeight - minHrText.height / 2));
    maxHrText.paint(canvas, Offset(0, -maxHrText.height / 2));

    // Draw x-axis time labels - dynamic based on time window
    final List<String> labels;
    final List<double> positions;
    
    if (displaySeconds <= 60) {
      // 0-60s: show 60s, 30s, 0s
      labels = ['1m', '0.5m', '0m'];
      positions = [0.0, 0.5, 1.0];
    } else if (displaySeconds <= 120) {
      // 60-120s: show 2m, 1m, 0m
      labels = ['2m', '1m', '0m'];
      positions = [0.0, 0.5, 1.0];
    } else if (displaySeconds <= 180) {
      // 120-180s: show 3m, 1.5m, 0m
      labels = ['3m', '1.5m', '0m'];
      positions = [0.0, 0.5, 1.0];
    } else if (displaySeconds <= 240) {
      // 180-240s: show 4m, 2m, 0m
      labels = ['4m', '2m', '0m'];
      positions = [0.0, 0.5, 1.0];
    } else {
      // 240-300s: show 5m, 2.5m, 0m
      labels = ['5m', '2.5m', '0m'];
      positions = [0.0, 0.5, 1.0];
    }

    for (int i = 0; i < labels.length; i++) {
      final label = labels[i];
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      
      final x = yAxisWidth + positions[i] * chartWidth - textPainter.width / 2;
      final y = chartHeight + 4;
      textPainter.paint(canvas, Offset(x, y));
    }

    // Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(yAxisWidth, 0),
      Offset(size.width, 0),
      gridPaint,
    );
    
    canvas.drawLine(
      Offset(yAxisWidth, chartHeight / 2),
      Offset(size.width, chartHeight / 2),
      gridPaint,
    );
    
    canvas.drawLine(
      Offset(yAxisWidth, chartHeight),
      Offset(size.width, chartHeight),
      gridPaint,
    );

    // Draw vertical grid line at midpoint
    canvas.drawLine(
      Offset(yAxisWidth + chartWidth * 0.5, 0),
      Offset(yAxisWidth + chartWidth * 0.5, chartHeight),
      gridPaint,
    );

    // Draw main axis lines
    final axisPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.4)
      ..strokeWidth = 1.5;

    // Y-axis
    canvas.drawLine(
      Offset(yAxisWidth, 0),
      Offset(yAxisWidth, chartHeight),
      axisPaint,
    );

    // X-axis
    canvas.drawLine(
      Offset(yAxisWidth, chartHeight),
      Offset(size.width, chartHeight),
      axisPaint,
    );

    // Draw HR line chart
    final linePaint = Paint()
      ..color = const Color(0xFFFF6B6B)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool firstPoint = true;
    
    final displayMilliseconds = displaySeconds * 1000.0;

    for (var i = 0; i < hrHistory.length; i++) {
      final dataPoint = hrHistory[i];
      
      // Skip data points outside the time window (before startTime)
      if (dataPoint.timestamp.isBefore(startTime)) continue;
      
      // Calculate x position based on timestamp (relative to dynamic time window)
      final timeDiff = dataPoint.timestamp.difference(startTime).inMilliseconds;
      final x = yAxisWidth + (timeDiff / displayMilliseconds) * chartWidth;
      
      // Calculate y position based on HR value
      final normalizedHr = (dataPoint.hr - paddedMin) / range;
      final y = chartHeight - (normalizedHr * chartHeight);

      if (firstPoint) {
        path.moveTo(x, y);
        firstPoint = false;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);

    // Draw dots at each data point
    final dotPaint = Paint()
      ..color = const Color(0xFFFF6B6B)
      ..style = PaintingStyle.fill;

    for (var dataPoint in hrHistory) {
      // Skip data points outside the time window (before startTime)
      if (dataPoint.timestamp.isBefore(startTime)) continue;
      
      final timeDiff = dataPoint.timestamp.difference(startTime).inMilliseconds;
      final x = yAxisWidth + (timeDiff / displayMilliseconds) * chartWidth;
      
      final normalizedHr = (dataPoint.hr - paddedMin) / range;
      final y = chartHeight - (normalizedHr * chartHeight);
      
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_HrChartPainter oldDelegate) {
    return hrHistory != oldDelegate.hrHistory;
  }
}
