import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';

enum ActivityLevel {
  resting(
    label: "Resting",
    icon: Icons.airline_seat_individual_suite,
    accelarationThreshold: 0.2,
    gyroscopeThreshold: 300,
  ),
  light(
    label: "Light",
    icon: Icons.directions_walk,
    accelarationThreshold: 0.4,
    gyroscopeThreshold: 600,
  ),
  moderate(
    label: "Moderate",
    icon: Icons.directions_run,
    accelarationThreshold: 0.8,
    gyroscopeThreshold: 1200,
  ),
  vigorous(
    label: "Vigorous",
    icon: Icons.fitness_center,
    accelarationThreshold: 2.0,
    gyroscopeThreshold: 3000,
  ),
  intense(
    label: "Intense",
    icon: Icons.local_fire_department,
    accelarationThreshold: double.infinity, // not needed
    gyroscopeThreshold: double.infinity, // not needed
  );

  final String label;
  final IconData icon;
  final double accelarationThreshold;
  final double gyroscopeThreshold;

  const ActivityLevel({
    required this.label,
    required this.icon,
    required this.accelarationThreshold,
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
  static const gravity = 9.81; // m/s^2

  final ValueNotifier<ActivityLevel> _activityLevel =
      ValueNotifier<ActivityLevel>(ActivityLevel.resting);
  ValueNotifier<ActivityLevel> get activityLevel => _activityLevel;
  final Stream<PpgMotionSample> accelerometerStream;
  final Stream<PpgMotionSample> gyroscopeStream;
  final int timestampExponentAccelerometer;
  final int timestampExponentGyroscope;

  final List<PpgMotionSample> _accelWindow = [];
  final List<PpgMotionSample> _gyroWindow = [];

  StreamSubscription<PpgMotionSample>? _accelerometerSubscription;
  StreamSubscription<PpgMotionSample>? _gyroscopeSubscription;

  DateTime? _lastEmitTime;
  static const Duration _emitInterval = Duration(seconds: 3);

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

  void stop() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
  }

  void reset() {
    _accelWindow.clear();
    _gyroWindow.clear();
    _activityLevel.value = ActivityLevel.resting;
  }

  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _activityLevel.dispose();
  }

  void simulateStress() {
    // Cancel subscriptions to stop processing real data
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();

    // Pretend that the user is resting for the stress period
    _activityLevel.value = ActivityLevel.resting;
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
    _accelWindow.removeWhere(
      (s) =>
          s.timestamp <
          sample.timestamp - 3 * pow(10, timestampExponentAccelerometer),
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
    _gyroWindow.removeWhere(
      (s) =>
          s.timestamp <
          sample.timestamp - 3 * pow(10, timestampExponentGyroscope),
    );
    // Update the activity level based on the current window of samples
    _updateActivityLevel();
  }

  void _updateActivityLevel() {
    if (_accelWindow.isEmpty || _gyroWindow.isEmpty) {
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

    if (avgAccelDeviation < ActivityLevel.resting.accelarationThreshold &&
        avgGyroMagnitude < ActivityLevel.resting.gyroscopeThreshold) {
      _activityLevel.value = ActivityLevel.resting;
    } else if (avgAccelDeviation < ActivityLevel.light.accelarationThreshold &&
        avgGyroMagnitude < ActivityLevel.light.gyroscopeThreshold) {
      _activityLevel.value = ActivityLevel.light;
    } else if (avgAccelDeviation <
            ActivityLevel.moderate.accelarationThreshold &&
        avgGyroMagnitude < ActivityLevel.moderate.gyroscopeThreshold) {
      _activityLevel.value = ActivityLevel.moderate;
    } else if (avgAccelDeviation <
            ActivityLevel.vigorous.accelarationThreshold &&
        avgGyroMagnitude < ActivityLevel.vigorous.gyroscopeThreshold) {
      _activityLevel.value = ActivityLevel.vigorous;
    } else {
      _activityLevel.value = ActivityLevel.intense;
    }
  }
}
