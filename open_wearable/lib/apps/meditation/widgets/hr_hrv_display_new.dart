import 'package:flutter/material.dart';

/// Modern widget to display current HR and HRV values
/// Inspired by Calm/Headspace design
class HrHrvDisplayNew extends StatelessWidget {
  final double hr;
  final double hrv;
  final double? sdnn; // Optional SDNN value (comparable to Apple Health)
  final String stressLevel;
  final bool isHrvStable; // New: indicates if HRV measurement is reliable
  final int? measurementDurationSeconds; // Timer for metrics requiring long measurement
  final String? activityLevel; // Activity level from accelerometer/gyroscope
  final String? activityDescription; // Human-readable activity description
  
  const HrHrvDisplayNew({
    super.key,
    required this.hr,
    required this.hrv,
    this.sdnn, // Optional: for Apple Health comparison
    required this.stressLevel,
    this.isHrvStable = true, // Default to true for backward compatibility
    this.measurementDurationSeconds,
    this.activityLevel,
    this.activityDescription,
  });
  
  @override
  Widget build(BuildContext context) {
    final Map<String, Color> stressColors = {
      'relaxed': const Color(0xFF51CF66),
      'normal': const Color(0xFFFFA500),
      'stressed': const Color(0xFFFF6B6B),
    };
    
    final Map<String, String> stressLabels = {
      'relaxed': 'Relaxed',
      'normal': 'Normal',
      'stressed': 'Stressed',
    };
    
    final Map<String, IconData> stressIcons = {
      'relaxed': Icons.check_circle_rounded,
      'normal': Icons.info_rounded,
      'stressed': Icons.warning_rounded,
    };
    
    final stressColor = stressColors[stressLevel] ?? const Color(0xFFFFA500);
    final stressText = stressLabels[stressLevel] ?? 'Normal';
    final stressIcon = stressIcons[stressLevel] ?? Icons.info_rounded;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.favorite,
                  iconColor: const Color(0xFFFF6B6B),
                  label: 'Heart Rate',
                  value: '${hr.toStringAsFixed(0)} BPM',
                  iconBackground: const Color(0xFFFFE5E5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.show_chart,
                  iconColor: const Color(0xFF4ECDC4),
                  label: 'RMSSD',
                  value: hrv < 0
                      ? 'Loading...'
                      : (isHrvStable 
                          ? '${hrv.toStringAsFixed(1)} ms' 
                          : 'Measuring...'),
                  iconBackground: const Color(0xFFE0F7F6),
                  isLoading: hrv < 0 || !isHrvStable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  icon: Icons.timeline,
                  iconColor: const Color(0xFF9C27B0),
                  label: 'SDNN',
                  value: (sdnn == null || sdnn! < 0)
                      ? '—'  // Em dash for pending
                      : (isHrvStable 
                          ? '${sdnn!.toStringAsFixed(1)} ms' 
                          : 'Measuring...'),
                  iconBackground: const Color(0xFFF3E5F5),
                  isLoading: (sdnn == null || sdnn! < 0) || !isHrvStable,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: stressColor.withOpacity(0.1),
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
                              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
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
