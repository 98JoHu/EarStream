import 'dart:math';
import 'package:logger/logger.dart';

final _logger = Logger();

/// Physical activity detection from IMU sensors in EARABLES
///
/// IMPORTANT: Earable sensors require MUCH HIGHER thresholds than wrist-worn devices!
/// 
/// Earables experience constant motion from:
/// - Head movements (nodding, turning, adjusting posture)
/// - Eating, talking, yawning (jaw motion affects ear canal)
/// - Walking/running (head oscillation patterns)
/// - Micro-movements that ear sensors detect but wrist sensors don't
///
/// Based on research by Stuchbury-Wass et al. (WalkEar, 2025) on earable activity recognition.
/// Thresholds calibrated specifically for in-ear IMU sensors.
///
/// Activity Levels:
/// - Resting: Minimal movement (normal daily activities)
/// - Light: Some movement detected
/// - Moderate: Clear activity patterns
/// - Vigorous: High activity
/// - Intense: Very high activity
///
/// Uses moving average window (30 samples ~3s) to smooth readings.
class ActivityDetector {
  // EARABLE-SPECIFIC THRESHOLDS (Fine-tuned based on real ear-worn testing!)
  // Thresholds based on deviation from 1g (static gravity)
  // When stationary, deviation ≈ 0g; when moving, deviation increases
  // Must distinguish: talking/looking around (resting) vs walking/exercising (active)
  // EARABLE-SPECIFIC THRESHOLDS (Fine-tuned for head movements)
  // Thresholds based on deviation from 1g (static gravity)
  static const double _restingAccelThreshold = 0.20; // g - Tolerance for head bobbing
  static const double _lightActivityAccelThreshold = 0.4; // g - 
  static const double _moderateActivityAccelThreshold = 0.8; // g - Brisk walking
  static const double _vigorousActivityAccelThreshold = 2.0; // g - Running (high impact)
  
  // Gyro: Natural head movements can be fast even when seated.
  // 300°/s allows for normal looking around without triggering "activity".
  // (User reported ~500°/s for slow movements).
  static const double _restingGyroThreshold = 300.0; // degrees/second
  
  // Moving average window
  final List<double> _accelMagnitudeHistory = [];
  final List<double> _gyroMagnitudeHistory = [];
  final int _windowSize = 30; // 30 samples ~3 seconds at 10Hz
  
  ActivityLevel _currentActivityLevel = ActivityLevel.resting;
  
  int _accelReadingCount = 0;
  
  /// Add new accelerometer reading (x, y, z in m/s²)
  void addAccelReading(double x, double y, double z) {
    _accelReadingCount++;
    
    // Convert to g units (1g = 9.81 m/s²)
    final gX = x / 9.81;
    final gY = y / 9.81;
    final gZ = z / 9.81;
    
    // Calculate total acceleration magnitude
    final totalMagnitude = sqrt(gX * gX + gY * gY + gZ * gZ);
    
    // Movement detection: deviation from 1g indicates acceleration (movement)
    // When stationary, magnitude ≈ 1g (gravity only)
    // When moving, magnitude deviates from 1g
    final deviation = (totalMagnitude - 1.0).abs();
    
    // Occasional summary (every 100 readings ~10 seconds)
    if (_accelReadingCount % 100 == 0) {
      _logger.d('ACCEL #$_accelReadingCount: dev=${deviation.toStringAsFixed(3)}g (thresh=${_restingAccelThreshold}g)');
    }
    
    _accelMagnitudeHistory.add(deviation);
    if (_accelMagnitudeHistory.length > _windowSize) {
      _accelMagnitudeHistory.removeAt(0);
    }
    
    _updateActivityLevel();
  }
  
  int _gyroReadingCount = 0;
  
  /// Add new gyroscope reading (x, y, z in rad/s)
  void addGyroReading(double x, double y, double z) {
    _gyroReadingCount++;
    
    // Convert to degrees/second
    final degX = x * 57.2958; // rad to deg
    final degY = y * 57.2958;
    final degZ = z * 57.2958;
    
    // Calculate angular velocity magnitude
    final magnitude = sqrt(degX * degX + degY * degY + degZ * degZ);
    
    // Occasional summary (every 100 readings ~10 seconds)
    if (_gyroReadingCount % 100 == 0) {
      _logger.d('GYRO #$_gyroReadingCount: mag=${magnitude.toStringAsFixed(1)}°/s (thresh=${_restingGyroThreshold}°/s)');
    }
    
    _gyroMagnitudeHistory.add(magnitude);
    if (_gyroMagnitudeHistory.length > _windowSize) {
      _gyroMagnitudeHistory.removeAt(0);
    }
    
    _updateActivityLevel();
  }
  
  int _updateCount = 0;
  
  void _updateActivityLevel() {
    if (_accelMagnitudeHistory.isEmpty) return;
    
    _updateCount++;
    
    // Calculate moving average
    final avgAccel = _accelMagnitudeHistory.reduce((a, b) => a + b) / _accelMagnitudeHistory.length;
    final avgGyro = _gyroMagnitudeHistory.isNotEmpty 
        ? _gyroMagnitudeHistory.reduce((a, b) => a + b) / _gyroMagnitudeHistory.length
        : 0.0;
    
    // Determine activity level based on BOTH sensors
    // Strategy: If BOTH are low → resting, otherwise use the sensor showing MORE activity
    ActivityLevel newLevel;
    String reason = '';
    
    // Both sensors must be below resting thresholds for "resting"
    if (avgAccel < _restingAccelThreshold && avgGyro < _restingGyroThreshold) {
      newLevel = ActivityLevel.resting;
      reason = 'both sensors calm';
    } else {
      // At least one sensor shows activity - determine level by the HIGHER reading
      // Map gyro to equivalent accel levels for comparison
      final gyroAsAccel = avgGyro / _restingGyroThreshold * _restingAccelThreshold;
      final maxActivity = avgAccel > gyroAsAccel ? avgAccel : gyroAsAccel;
      
      if (maxActivity < _lightActivityAccelThreshold) {
        newLevel = ActivityLevel.light;
        reason = avgAccel > gyroAsAccel ? 'accel movement' : 'gyro movement';
      } else if (maxActivity < _moderateActivityAccelThreshold) {
        newLevel = ActivityLevel.moderate;
        reason = 'moderate movement';
      } else if (maxActivity < _vigorousActivityAccelThreshold) {
        newLevel = ActivityLevel.vigorous;
        reason = 'vigorous movement';
      } else {
        newLevel = ActivityLevel.intense;
        reason = 'intense movement';
      }
    }
    
    // Update if changed (ONLY log when activity level changes)
    if (newLevel != _currentActivityLevel) {
      _logger.i('Activity: ${_currentActivityLevel.name} → ${newLevel.name} '
                '(accel=${avgAccel.toStringAsFixed(3)}g, gyro=${avgGyro.toStringAsFixed(1)}°/s) - $reason');
      _currentActivityLevel = newLevel;
    }
  }
  
  /// Get current activity level
  ActivityLevel get activityLevel => _currentActivityLevel;
  
  /// Check if user is currently resting (not exercising)
  bool get isResting => _currentActivityLevel == ActivityLevel.resting;
  
  /// Check if activity might explain elevated heart rate
  /// Returns true for moderate+ activity (user is likely exercising)
  bool get isExercising => _currentActivityLevel.index >= ActivityLevel.moderate.index;
  
  /// Get average acceleration over window (in g units)
  double get averageAcceleration {
    if (_accelMagnitudeHistory.isEmpty) return 0.0;
    return _accelMagnitudeHistory.reduce((a, b) => a + b) / _accelMagnitudeHistory.length;
  }
  
  /// Get average gyroscope magnitude over window (in degrees/second)
  double get averageGyroMagnitude {
    if (_gyroMagnitudeHistory.isEmpty) return 0.0;
    return _gyroMagnitudeHistory.reduce((a, b) => a + b) / _gyroMagnitudeHistory.length;
  }
  
  /// Reset detector
  void reset() {
    _accelMagnitudeHistory.clear();
    _gyroMagnitudeHistory.clear();
    _currentActivityLevel = ActivityLevel.resting;
  }
}

/// Activity levels based on accelerometer/gyroscope data
enum ActivityLevel {
  resting,   // Sitting, standing still
  light,     // Slow walking, gentle movement
  moderate,  // Brisk walking, light exercise
  vigorous,  // Running, active exercise
  intense,   // Sprinting, very intense exercise
}
