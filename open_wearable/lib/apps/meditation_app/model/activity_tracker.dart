import 'package:flutter/foundation.dart';
import 'dart:math';
import 'dart:async';

import '../configs/bio_adaptive_mode_config.dart';

enum ActivityLevel {
  resting(
    accelerationThreshold: BioAdaptiveModeConfig.restingAccelerationThreshold,
    gyroscopeThreshold: BioAdaptiveModeConfig.restingGyroscopeThreshold,
  ),
  light(
    accelerationThreshold: BioAdaptiveModeConfig.lightAccelerationThreshold,
    gyroscopeThreshold: BioAdaptiveModeConfig.lightGyroscopeThreshold,
  ),
  moderate(
    accelerationThreshold: BioAdaptiveModeConfig.moderateAccelerationThreshold,
    gyroscopeThreshold: BioAdaptiveModeConfig.moderateGyroscopeThreshold,
  ),
  vigorous(
    accelerationThreshold: BioAdaptiveModeConfig.vigorousAccelerationThreshold,
    gyroscopeThreshold: BioAdaptiveModeConfig.vigorousGyroscopeThreshold,
  ),
  intense(
    accelerationThreshold: double.infinity, // not needed
    gyroscopeThreshold: double.infinity, // not needed
  );

  final double accelerationThreshold;
  final double gyroscopeThreshold;

  const ActivityLevel({
    required this.accelerationThreshold,
    required this.gyroscopeThreshold,
  });
}

class PpgMotionSample {
  final int timestamp;
  final double x;
  final double y;
  final double z;

  const PpgMotionSample({
    required this.timestamp,
    required this.x,
    required this.y,
    required this.z,
  });

  double get magnitude => sqrt((x * x) + (y * y) + (z * z));
  double get deviation => (magnitude - 1.0).abs();
}

class ActivityTracker {
  static const gravity =
      BioAdaptiveModeConfig.gravityMetersPerSecondSquared; // m/s^2

  final ValueNotifier<ActivityLevel> _activityLevel =
      ValueNotifier<ActivityLevel>(ActivityLevel.resting);
  ValueListenable<ActivityLevel> get activityLevel => _activityLevel;
  final Stream<PpgMotionSample> accelerometerStream;
  final Stream<PpgMotionSample> gyroscopeStream;
  final int timestampExponentAccelerometer;
  final int timestampExponentGyroscope;

  final List<PpgMotionSample> _accelWindow = [];
  final List<PpgMotionSample> _gyroWindow = [];

  StreamSubscription<PpgMotionSample>? _accelerometerSubscription;
  StreamSubscription<PpgMotionSample>? _gyroscopeSubscription;

  DateTime? _lastEmitTime;
  static const Duration _emitInterval =
      BioAdaptiveModeConfig.activityClassificationInterval;
  static const Duration _classificationWindow =
      BioAdaptiveModeConfig.activityClassificationInterval;

  // Rolling history of classified activity levels, used to suppress stress
  // detection during/after sustained physical activity (see
  // shouldSuppressStressDetection).
  final List<(DateTime, ActivityLevel)> _activityHistory = [];
  static const Duration _activityHistoryWindow =
      BioAdaptiveModeConfig.activityHistoryWindow;
  static const double _lightOrMoreSuppressionRatio =
      BioAdaptiveModeConfig.lightActivitySuppressionRatio;
  static const double _moderateOrMoreSuppressionRatio =
      BioAdaptiveModeConfig.moderateActivitySuppressionRatio;
  static const double _vigorousOrMoreSuppressionRatio =
      BioAdaptiveModeConfig.vigorousActivitySuppressionRatio;
  static const double _intenseSuppressionRatio =
      BioAdaptiveModeConfig.intenseActivitySuppressionRatio;

  ActivityTracker({
    required this.accelerometerStream,
    required this.gyroscopeStream,
    required this.timestampExponentAccelerometer,
    required this.timestampExponentGyroscope,
  });

  void start() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _accelerometerSubscription =
        accelerometerStream.listen(_processAccelerometerData);
    _gyroscopeSubscription = gyroscopeStream.listen(_processGyroscopeData);
  }

  void pause() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
  }

  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _activityLevel.dispose();
  }

  bool shouldSuppressStressDetection() {
    final now = DateTime.now();
    _activityHistory.removeWhere(
      (entry) => now.difference(entry.$1) > _activityHistoryWindow,
    );
    return shouldSuppressForLevels(_activityHistory.map((entry) => entry.$2));
  }

  /// Applies the documented five-minute-history percentage rules to already
  /// classified samples. Kept pure so the policy can be regression-tested
  /// independently from live sensor timing.
  static bool shouldSuppressForLevels(Iterable<ActivityLevel> levels) {
    final history = levels.toList(growable: false);
    if (history.isEmpty) {
      return false;
    }

    double ratioAtLeast(ActivityLevel level) {
      final count = history.where((entry) => entry.index >= level.index).length;
      return count / history.length;
    }

    return ratioAtLeast(ActivityLevel.light) >= _lightOrMoreSuppressionRatio ||
        ratioAtLeast(ActivityLevel.moderate) >=
            _moderateOrMoreSuppressionRatio ||
        ratioAtLeast(ActivityLevel.vigorous) >=
            _vigorousOrMoreSuppressionRatio ||
        ratioAtLeast(ActivityLevel.intense) >= _intenseSuppressionRatio;
  }

  void _processAccelerometerData(PpgMotionSample sample) {
    // Convert to g units
    sample = PpgMotionSample(
      timestamp: sample.timestamp,
      x: sample.x / gravity,
      y: sample.y / gravity,
      z: sample.z / gravity,
    );

    // Add the sample to the window and remove old samples
    _accelWindow.add(sample);
    _trimToClassificationWindow(
      _accelWindow,
      sample.timestamp,
      timestampExponentAccelerometer,
    );

    // Update the activity level based on the current window of samples
    _updateActivityLevel();
  }

  void _processGyroscopeData(PpgMotionSample sample) {
    // Convert to degrees/s units
    sample = PpgMotionSample(
      timestamp: sample.timestamp,
      x: sample.x * 180 / pi,
      y: sample.y * 180 / pi,
      z: sample.z * 180 / pi,
    );

    // Add the sample to the window and remove old samples
    _gyroWindow.add(sample);
    _trimToClassificationWindow(
      _gyroWindow,
      sample.timestamp,
      timestampExponentGyroscope,
    );
    // Update the activity level based on the current window of samples
    _updateActivityLevel();
  }

  void _updateActivityLevel() {
    if (!_coversClassificationWindow(
          _accelWindow,
          timestampExponentAccelerometer,
        ) ||
        !_coversClassificationWindow(
          _gyroWindow,
          timestampExponentGyroscope,
        )) {
      return;
    }

    final now = DateTime.now();
    if (_lastEmitTime != null &&
        now.difference(_lastEmitTime!) < _emitInterval) {
      return;
    }
    _lastEmitTime = now;

    // Calculate the average magnitude of the accelerometer and gyroscope data
    final avgAccelDeviation =
        _accelWindow.map((s) => s.deviation).reduce((a, b) => a + b) /
            _accelWindow.length;
    final avgGyroMagnitude =
        _gyroWindow.map((s) => s.magnitude).reduce((a, b) => a + b) /
            _gyroWindow.length;

    final level = classify(
      accelerationDeviationG: avgAccelDeviation,
      gyroscopeMagnitudeDegreesPerSecond: avgGyroMagnitude,
    );

    _activityLevel.value = level;
    _activityHistory.add((now, level));
    _activityHistory.removeWhere(
      (entry) => now.difference(entry.$1) > _activityHistoryWindow,
    );
  }

  static bool _coversClassificationWindow(
    List<PpgMotionSample> samples,
    int timestampExponent,
  ) {
    if (samples.length < 2) return false;
    final requiredTicks = classificationWindowTicksFor(timestampExponent);
    return samples.last.timestamp - samples.first.timestamp >= requiredTicks;
  }

  static void _trimToClassificationWindow(
    List<PpgMotionSample> samples,
    int latestTimestamp,
    int timestampExponent,
  ) {
    final cutoff =
        latestTimestamp - classificationWindowTicksFor(timestampExponent);
    var retainedPredecessor = 0;
    while (retainedPredecessor + 1 < samples.length &&
        samples[retainedPredecessor + 1].timestamp <= cutoff) {
      retainedPredecessor++;
    }
    if (retainedPredecessor > 0) {
      samples.removeRange(0, retainedPredecessor);
    }
  }

  static double classificationWindowTicksFor(int timestampExponent) {
    final ticksPerSecond = pow(10, -timestampExponent).toDouble();
    return _classificationWindow.inMicroseconds / 1000000.0 * ticksPerSecond;
  }

  /// Classifies a three-second window. A window advances to the next level if
  /// either motion measure reaches that level, which is equivalent to both
  /// measures having to remain below a level's upper bounds.
  static ActivityLevel classify({
    required double accelerationDeviationG,
    required double gyroscopeMagnitudeDegreesPerSecond,
  }) {
    if (accelerationDeviationG < ActivityLevel.resting.accelerationThreshold &&
        gyroscopeMagnitudeDegreesPerSecond <
            ActivityLevel.resting.gyroscopeThreshold) {
      return ActivityLevel.resting;
    } else if (accelerationDeviationG <
            ActivityLevel.light.accelerationThreshold &&
        gyroscopeMagnitudeDegreesPerSecond <
            ActivityLevel.light.gyroscopeThreshold) {
      return ActivityLevel.light;
    } else if (accelerationDeviationG <
            ActivityLevel.moderate.accelerationThreshold &&
        gyroscopeMagnitudeDegreesPerSecond <
            ActivityLevel.moderate.gyroscopeThreshold) {
      return ActivityLevel.moderate;
    } else if (accelerationDeviationG <
            ActivityLevel.vigorous.accelerationThreshold &&
        gyroscopeMagnitudeDegreesPerSecond <
            ActivityLevel.vigorous.gyroscopeThreshold) {
      return ActivityLevel.vigorous;
    } else {
      return ActivityLevel.intense;
    }
  }
}
