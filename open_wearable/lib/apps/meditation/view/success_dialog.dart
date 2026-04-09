import 'package:flutter/material.dart';

class SuccessDialog extends StatelessWidget {
  final double hrBefore;
  final double hrvRmssdBefore;
  final double hrvSdnnBefore;
  final double hrAfter;
  final double hrvRmssdAfter;
  final double hrvSdnnAfter;

  const SuccessDialog({
    Key? key,
    required this.hrBefore,
    required this.hrvRmssdBefore,
    required this.hrvSdnnBefore,
    required this.hrAfter,
    required this.hrvRmssdAfter,
    required this.hrvSdnnAfter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hrImprovement = hrBefore - hrAfter;
    final hrvRmssdImprovement = hrvRmssdAfter - hrvRmssdBefore;
    final hrvSdnnImprovement = hrvSdnnAfter - hrvSdnnBefore;
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF51CF66).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 40,
                  color: Color(0xFF51CF66),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Well Done!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You are feeling calmer now',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _MetricComparison(
                      icon: Icons.favorite,
                      iconColor: const Color(0xFFFF6B6B),
                      label: 'Heart Rate',
                      before: hrBefore,
                      after: hrAfter,
                      unit: 'BPM',
                      improvement: hrImprovement,
                      improvementIsPositive: hrImprovement > 0,
                    ),
                    const SizedBox(height: 12),
                    _MetricComparison(
                      icon: Icons.show_chart,
                      iconColor: const Color(0xFF4ECDC4),
                      label: 'RMSSD',
                      before: hrvRmssdBefore,
                      after: hrvRmssdAfter,
                      unit: 'ms',
                      improvement: hrvRmssdImprovement,
                      improvementIsPositive: hrvRmssdImprovement > 0,
                    ),
                    const SizedBox(height: 12),
                    _MetricComparison(
                      icon: Icons.timeline,
                      iconColor: const Color(0xFF9B59B6),
                      label: 'SDNN',
                      before: hrvSdnnBefore,
                      after: hrvSdnnAfter,
                      unit: 'ms',
                      improvement: hrvSdnnImprovement,
                      improvementIsPositive: hrvSdnnImprovement > 0,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
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

class _MetricComparison extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final double before;
  final double after;
  final String unit;
  final double improvement;
  final bool improvementIsPositive;

  const _MetricComparison({
    Key? key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.before,
    required this.after,
    required this.unit,
    required this.improvement,
    required this.improvementIsPositive,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Determine if this is an HRV metric (RMSSD or SDNN)
    final isHrvMetric = label == 'RMSSD' || label == 'SDNN';
    
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Before',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${before.toStringAsFixed(isHrvMetric ? 1 : 0)} $unit',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
              child: Icon(
                Icons.arrow_forward,
                size: 16,
                color: Colors.grey[400],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'After',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${after.toStringAsFixed(isHrvMetric ? 1 : 0)} $unit',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[800],
                        ),
                      ),
                      if (improvement.abs() > 0.1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: improvementIsPositive
                                ? const Color(0xFF51CF66)
                                : const Color(0xFFFF6B6B),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${improvementIsPositive ? '+' : ''}${improvement.toStringAsFixed(isHrvMetric ? 1 : 0)}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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
      ],
    );
  }
}
