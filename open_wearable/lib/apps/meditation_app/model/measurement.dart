import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'band_pass_filter.dart';
import 'dart:math';

enum ActivityLevel {
  resting(
    label: "Resting",
    icon: Icons.airline_seat_individual_suite,
  ),
  light(
    label: "Light",
    icon: Icons.directions_walk,
  ),
  moderate(
    label: "Moderate",
    icon: Icons.directions_run,
  ),
  vigorous(
    label: "Vigorous",
    icon: Icons.fitness_center,
  ),
  intense(
    label: "Intense",
    icon: Icons.local_fire_department,
  );

  final String label;
  final IconData icon;

  const ActivityLevel({
    required this.label,
    required this.icon,
  });
}

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

enum MonitoringPhase {
  calibration(
    label: "Calibration (30s)",
    icon: Icons.settings_outlined,
    duration: Duration(seconds: 30),
    color: Colors.orange,
  ),
  baseline(
    label: "Monitoring \u00b7 Baseline Adjustment",
    icon: Icons.straighten_outlined,
    duration: Duration(minutes: 5),
    color: Colors.blue,
  ),
  monitoring(
    label: "Monitoring",
    icon: Icons.monitor_heart,
    duration: Duration(),
    color: Color(0xFF4ECDC4),
  ),
  meditation(
    label: "Meditation",
    icon: Icons.self_improvement_outlined,
    duration: Duration(),
    color: Colors.purple,
  );

  final String label;
  final IconData icon;
  final Duration duration;
  final Color color;

  const MonitoringPhase({
    required this.label,
    required this.icon,
    required this.duration,
    required this.color,
  });
}

class PpgOpticalSample {
  final int timestamp;
  final double red;
  final double ir;
  final double green;
  final double ambient;

  const PpgOpticalSample({
    required this.timestamp,
    required this.red,
    required this.ir,
    required this.green,
    required this.ambient,
  });
}

class Measurement {
  final Sensor ppgSensor;
  final Sensor accelerometerSensor;
  final Sensor gyroscopeSensor;
  final SensorConfigurationProvider sensorConfigProvider;

  // PPG data stream: emits a tuple of (timestamp, value) where value is the sum of green and ambient channels (inverted).
  late final Stream<(int, double)> _ppgStream;
  Stream<int?> _heartRate = Stream.empty();
  Stream<int?> get heartRate => _heartRate;
  Stream<double> _rmssd = Stream.empty();
  Stream<double> get rmssd => _rmssd;

  Measurement({
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
  }) {
    _configureSensorForStreaming(
      ppgSensor,
      sensorConfigProvider,
      fallbackFrequency: 50.0,
      targetFrequencyHz: 50,
    );

    final ppgStream = ppgSensor.sensorStream
        .map<PpgOpticalSample?>((data) {
          final values = _sensorValuesAsDoubles(data);
          if (values == null) {
            return null;
          }
          return _extractPpgOpticalSample(ppgSensor, data, values);
        })
        .where((sample) => sample != null)
        .map<(int, double)>(
          (sample) => (sample!.timestamp, -(sample.green + sample.ambient)),
        )
        .asBroadcastStream();
    _ppgStream = ppgStream;
  }

  void start() {
    _heartRate = deriveHeartRate(_ppgStream);
    _rmssd = deriveRmssd(_ppgStream);
  }

  Stream<int?> deriveHeartRate(Stream<(int, double)> ppgStream) {
    // 1. Band pass filter the PPG signal to remove noise and artifacts.
    final bandPassFilter =
        BandPassFilter(lowCut: 0.5, highCut: 4.0, sampleFreq: 200.0);
    // 2. Smooth the filtered signal
    final movingAverageFilter = MovingAverageFilter();
    // 3. Detect peaks in the filtered PPG
    final peakDetector = SlidingWindowPeakDetector(
      windowDurationSeconds: 8,
      minInterPeakDistanceMs: 300,
      timestampExponent: ppgSensor.timestampExponent,
    );
    // 4. Smooth the heart rate using a Kalman filter
    final kalmanFilter = KalmanFilter(q: 0.01, r: 4.0);
    return ppgStream.map(
      (event) {
        final (timestamp, value) = event;
        print("PPG Sample: timestamp=$timestamp, value=$value");
        final filteredValue = bandPassFilter.filter(value);
        final smoothedValue = movingAverageFilter.next(filteredValue);
        final int? peakTimestamp =
            peakDetector.processSample(timestamp, smoothedValue);
        if (peakTimestamp == null) return null;
        final peaks = peakDetector.activePeaks;
        if (peaks.length < 2) return null;

        double totalIbiMs = 0.0;
        int ibiCount = 0;

        for (var i = 1; i < peaks.length; i++) {
          final double ibi = (peaks[i] - peaks[i - 1]) *
              pow(10, ppgSensor.timestampExponent + 3)
                  .toDouble(); // Convert to milliseconds
          totalIbiMs += ibi;
          ibiCount++;
        }

        final averageIbiMs = totalIbiMs / ibiCount;
        if (averageIbiMs <= 0 ||
            averageIbiMs.isNaN ||
            averageIbiMs.isInfinite) {
          return null;
        }

        final double heartRate =
            60000.0 / averageIbiMs; // Convert to beats per minute

        final smoothedHeartRate = kalmanFilter.update(heartRate);

        return smoothedHeartRate.round();
      },
    );
  }

  Stream<double> deriveRmssd(Stream<(int, double)> ppgStream) {
    // 1. Band pass filter the PPG signal to remove noise and artifacts.

    // 2. Detect peaks in the filtered PPG signal to identify heartbeats.
    // 3. Calculate the time intervals between consecutive peaks (RR intervals).
    // 4. Compute the differences between successive RR intervals.
    // 5. Square the differences and calculate the mean of these squared differences.
    // 6. Take the square root of the mean to obtain RMSSD.
    return ppgStream.map((_) => 0.0); // Placeholder implementation
  }

  List<double>? _sensorValuesAsDoubles(SensorValue data) {
    if (data is SensorDoubleValue) {
      return data.values;
    }
    if (data is SensorIntValue) {
      return data.values
          .map((value) => value.toDouble())
          .toList(growable: false);
    }
    return null;
  }

  PpgOpticalSample? _extractPpgOpticalSample(
    Sensor sensor,
    SensorValue data,
    List<double> values,
  ) {
    if (values.isEmpty) {
      return null;
    }

    int? findAxisIndex(List<String> keywords) {
      for (var i = 0; i < sensor.axisNames.length; i++) {
        final axis = sensor.axisNames[i].toLowerCase();
        if (keywords.any(axis.contains)) {
          return i;
        }
      }
      return null;
    }

    double valueAt(int? index, double fallback) {
      if (index != null && index >= 0 && index < values.length) {
        return values[index];
      }
      return fallback;
    }

    final fallbackRed = values[0];
    final fallbackIr = values.length > 1 ? values[1] : fallbackRed;
    final fallbackGreen = values.length > 2 ? values[2] : fallbackRed;
    final fallbackAmbient = values.length > 3 ? values[3] : 0.0;

    // Usually channels are [red, ir, green, ambient], but we prefer axis-name
    // matching when available to avoid firmware-order mismatches.
    final red = valueAt(findAxisIndex(['red']), fallbackRed);
    final ir = valueAt(findAxisIndex(['ir', 'infrared']), fallbackIr);
    final green = valueAt(findAxisIndex(['green']), fallbackGreen);
    final ambient = valueAt(findAxisIndex(['ambient']), fallbackAmbient);

    return PpgOpticalSample(
      timestamp: data.timestamp,
      red: red,
      ir: ir,
      green: green,
      ambient: ambient,
    );
  }

  double _configureSensorForStreaming(
    Sensor sensor,
    SensorConfigurationProvider configProvider, {
    required double fallbackFrequency,
    required int targetFrequencyHz,
  }) {
    final configuration = sensor.relatedConfigurations.firstOrNull;
    if (configuration == null) {
      return fallbackFrequency;
    }

    if (configuration is ConfigurableSensorConfiguration &&
        configuration.availableOptions.contains(StreamSensorConfigOption())) {
      configProvider.addSensorConfigurationOption(
        configuration,
        StreamSensorConfigOption(),
        markPending: false,
      );
    }

    final values = configProvider.getSensorConfigurationValues(
      configuration,
      distinct: true,
    );
    SensorConfigurationValue? appliedValue;
    if (values.isNotEmpty) {
      appliedValue = _selectBestConfigurationValue(
        values,
        targetFrequencyHz: targetFrequencyHz,
      );
      configProvider.addSensorConfiguration(
        configuration,
        appliedValue,
        markPending: false,
      );
    }

    final selectedValue =
        configProvider.getSelectedConfigurationValue(configuration) ??
            appliedValue;
    if (selectedValue != null) {
      configuration.setConfiguration(selectedValue);
    }

    if (selectedValue is SensorFrequencyConfigurationValue) {
      return selectedValue.frequencyHz;
    }

    return fallbackFrequency;
  }

  SensorConfigurationValue _selectBestConfigurationValue(
    List<SensorConfigurationValue> values, {
    required int targetFrequencyHz,
  }) {
    final frequencyValues =
        values.whereType<SensorFrequencyConfigurationValue>().toList();
    if (frequencyValues.isEmpty) {
      return values.first;
    }

    SensorFrequencyConfigurationValue? nextBigger;
    SensorFrequencyConfigurationValue? maxValue;
    for (final value in frequencyValues) {
      if (maxValue == null || value.frequencyHz > maxValue.frequencyHz) {
        maxValue = value;
      }
      if (value.frequencyHz >= targetFrequencyHz &&
          (nextBigger == null || value.frequencyHz < nextBigger.frequencyHz)) {
        nextBigger = value;
      }
    }

    return nextBigger ?? maxValue ?? values.first;
  }
}

class MovingAverageFilter {
  final int windowSize = 9;
  final List<double> _buffer = [];
  double _currentSum = 0.0;

  /// Process a single sample through the 9-sample moving average
  double next(double sample) {
    // Add the new sample to our window
    _buffer.add(sample);
    _currentSum += sample;

    // If the window exceeds 9 items, drop the oldest sample
    if (_buffer.length > windowSize) {
      _currentSum -= _buffer.removeAt(0);
    }

    // Return the average of the current window
    return _currentSum / _buffer.length;
  }
}

class SlidingWindowPeakDetector {
  late num windowDuration;
  late num minInterPeakDistance;
  final int timestampExponent;

  SlidingWindowPeakDetector({
    required int windowDurationSeconds,
    required int minInterPeakDistanceMs,
    required this.timestampExponent,
  }) {
    windowDuration = windowDurationSeconds * pow(10, -timestampExponent);
    minInterPeakDistance =
        minInterPeakDistanceMs * pow(10, -timestampExponent - 3);
  }

  // Stores the historical clean samples: Tuple of (timestampUs, value)
  final List<(int, double)> _history = [];
  final List<int> _peakTimestamps = [];

  /// Processes a single filtered/smoothed sample.
  /// Returns a valid peak timestamp (in microseconds) if a peak was just found, otherwise null.
  int? processSample(int timestamp, double value) {
    // 1. Add current sample to our tracking history
    _history.add((timestamp, value));

    // 2. Slide the window: Drop elements older than 8 seconds
    _history.removeWhere((sample) => sample.$1 < timestamp - windowDuration);

    // 3. We need at least 3 samples in history to evaluate a local maximum turning point
    if (_history.length < 3) return null;

    // Grab the last three sequential samples in our history buffer
    final idx = _history.length - 1;
    final (_, vPrev) = _history[idx - 2];
    final (tCurr, vCurr) = _history[idx - 1]; // We evaluate the middle point
    final (_, vNext) = _history[idx];

    // 4. Check if the middle point represents a mathematical local maximum peak
    if (vCurr > vPrev && vCurr >= vNext) {
      // 5. Enforce minimum inter-peak lockout distance constraint
      final lastPeak = _peakTimestamps.isNotEmpty ? _peakTimestamps.last : 0;
      if (tCurr - lastPeak >= minInterPeakDistance) {
        // Valid peak found! Record it and clean up peak history older than 8 seconds
        _peakTimestamps.add(tCurr);
        _peakTimestamps.removeWhere(
          (peakTime) => peakTime < timestamp - windowDuration,
        );

        return tCurr;
      }
    }

    return null;
  }

  /// Exposes the list of peak timestamps currently residing within the 8-second window
  List<int> get activePeaks => List.unmodifiable(_peakTimestamps);
}

class KalmanFilter {
  // Parameters
  final double q; // Process noise covariance
  final double r; // Measurement noise covariance

  KalmanFilter({required this.q, required this.r});

  // Filter State Variables
  double _x = 0.0; // Estimated true state value
  double _p = 1.0; // Estimation error covariance
  bool _isInitialized = false;

  /// Processes a single noisy sample and returns the smoothed estimate
  double update(double measurement) {
    // 1. Handle initialization on the very first sample
    if (!_isInitialized) {
      _x = measurement;
      _isInitialized = true;
      return _x;
    }

    // 2. PREDICT STEP
    // For a simple 1D system, the state prediction remains the same,
    // but our uncertainty grows by the process noise Q.
    _p = _p + q;

    // 3. UPDATE STEP
    // Calculate the Kalman Gain (K)
    double k = _p / (_p + r);

    // Correct the state estimate using the new measurement
    _x = _x + k * (measurement - _x);

    // Update the error covariance for the next loop
    _p = (1.0 - k) * _p;

    return _x;
  }
}
