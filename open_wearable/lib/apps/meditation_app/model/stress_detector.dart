import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'hr_hrv_processor.dart' show HeartRateSample;

enum StressLevel {
  relaxed(
    label: "Relaxed",
    icon: Icons.spa_rounded,
    color: Colors.green,
    backgroundColor: Color(0xFFC8E6C9),
  ),
  stressed(
    label: "Stressed",
    icon: Icons.bolt_rounded,
    color: Colors.red,
    backgroundColor: Color(0xFFFFCDD2),
  );

  final String label;
  final IconData icon;
  final Color color;
  final Color backgroundColor;

  const StressLevel({
    required this.label,
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });
}

typedef StressThresholdProvider = (int heartRate, double rmssd) Function();
typedef BaselineHeartRateProvider = int Function();

class StressDetector {
  final StressThresholdProvider _thresholds;
  final BaselineHeartRateProvider _baselineHeartRate;
  final ValueNotifier<StressLevel> _level = ValueNotifier(StressLevel.relaxed);

  StressDetector({
    required StressThresholdProvider thresholds,
    required BaselineHeartRateProvider baselineHeartRate,
  })  : _thresholds = thresholds,
        _baselineHeartRate = baselineHeartRate;

  ValueListenable<StressLevel> get stressLevel => _level;
  StressLevel get currentStressLevel => _level.value;

  void onSample(HeartRateSample sample, {required bool suppress}) {
    if (_level.value == StressLevel.stressed) {
      _trackRecovery(sample.heartRate);
      return;
    }

    if (suppress) return;

    if (_isStressed(sample.heartRate, sample.rmssd)) {
      _level.value = StressLevel.stressed;
    }
  }

  void reset() => _level.value = StressLevel.relaxed;

  void dispose() => _level.dispose();

  bool _isStressed(int heartRate, double? rmssd) {
    final (hrThreshold, rmssdThreshold) = _thresholds();
    return heartRate > hrThreshold && rmssd != null && rmssd < rmssdThreshold;
  }

  void _trackRecovery(int heartRate) {
    if (heartRate <= _baselineHeartRate()) {
      _level.value = StressLevel.relaxed;
    }
  }
}
