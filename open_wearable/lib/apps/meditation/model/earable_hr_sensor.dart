import 'dart:async';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/apps/meditation/model/ppg_filter_meditation.dart';
import 'package:open_wearable/apps/meditation/model/hrv_calculator.dart';
import 'package:logger/logger.dart';
import 'hr_sensor_interface.dart';
import 'activity_detector.dart';

import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

final _logger = Logger();

/// Real sensor that connects to the OpenEarable device and computes HR/HRV from PPG data.
class EarableHrSensor implements HrSensorInterface {
  final Sensor ppgSensor;
  final Wearable wearable;
  final double sampleFreq;
  final SensorConfigurationProvider? configProvider;
  
  // ignore: unused_field
  final SensorManager sensorManager; 
  
  final StreamController<double> _hrController = StreamController<double>.broadcast();
  final StreamController<Map<String, double>> _hrvController = StreamController<Map<String, double>>.broadcast();
  // Controller for connection state
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  
  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<List<double>>? _rrIntervalSubscription;
  StreamSubscription<SensorValue>? _accelSubscription;
  StreamSubscription<SensorValue>? _gyroSubscription;
  Timer? _hrvTimer;
  bool _isActive = false;
  double _currentHr = 0.0; // Current HR value storage
  
  final ActivityDetector activityDetector = ActivityDetector();
  
  final List<double> _rrIntervals = [];
  final int _maxRrIntervals = 50; 
  final int _minRrIntervalsForStableHrv = 10; 
  final int _minRrIntervalsForSdnn = 30; 
  final int _maxLongTermRrIntervals = 300; 
  final List<double> _longTermRrIntervals = []; 
  
  // History for charts
  final List<double> _hrHistory = [];
  final List<double> _hrvHistory = [];
  final int _maxHistorySize = 3600; 
  
  final HrvCalculator _hrvCalculator = HrvCalculator();
  bool _hrvIsStable = false; 
  
  /// Stream of heart rate values in BPM
  Stream<double> get hrStream => _hrController.stream;
  
  /// Stream of HRV metrics (SDNN, RMSSD, pNN50)
  Stream<Map<String, double>> get hrvStream => _hrvController.stream;
  
  /// Stream of connection state
  @override
  Stream<bool> get isConnected => _connectionController.stream;
  
  /// Get HR history for charts
  List<double> get hrHistory => List.unmodifiable(_hrHistory);
  
  /// Get measured HR
  double get currentHr => _currentHr;

  double get lastAccelMagnitude => activityDetector.averageAcceleration;
  
  /// Get HRV history for charts
  List<double> get hrvHistory => List.unmodifiable(_hrvHistory);
  
  EarableHrSensor({
    required this.ppgSensor,
    required this.wearable,
    required this.sensorManager,
    required this.sampleFreq,
    this.configProvider,
  });
  
  /// Start generating real data from the earable device
  Future<void> start() async {
    _logger.i('start() called! _isActive=$_isActive');
    
    if (_isActive) {
      _logger.w('start() returning early because _isActive is already true!');
      return;
    }
    
    _isActive = true;
    _logger.i(' Set _isActive = true');
    
    _logger.i('Starting EarableHrSensor with sample frequency: $sampleFreq Hz');
    
    // Start IMU sensors for activity detection
    _startImuSensors();
    
    // PPG sensor is already configured in meditation_view.dart before this sensor is created
    // Calling _startPpgSensor() here would reconfigure it and break the stream!
    // _logger.i('🩺 CALLING _startPpgSensor()...');
    // _startPpgSensor();
    // _logger.i(' _startPpgSensor() completed');
    _logger.i('PPG sensor already configured by meditation_view.dart');
    
    _logger.i('Sensors started: IMU (Safe Mode) & PPG');
    
    // Initial connection state
    _connectionController.add(true);
        
    // Listen for disconnects
    // Note: OpenEarable API doesn't support removing listeners, so this accumulates.
    // We protect against closed controller usage.
    wearable.addDisconnectListener(() {
      if (!_connectionController.isClosed) {
        _logger.w('Device disconnected!');
        _connectionController.add(false);
      }
    });

    // Create PPG filter to extract heart rate AND RR intervals
    _logger.i('Creating PPG filter from ppgSensor.sensorStream...');
    _logger.i('PPG Sensor: ${ppgSensor.sensorName}, Stream: ${ppgSensor.sensorStream}');
    
    // Test if PPG stream is actually emitting data
    bool ppgStreamActive = false;
    final testSubscription = ppgSensor.sensorStream.timeout(
      Duration(seconds: 2),
      onTimeout: (sink) {
        _logger.e('PPG sensor stream TIMEOUT - no data received in 2 seconds!');
        sink.close();
      },
    ).listen((data) {
      ppgStreamActive = true;
      _logger.i('PPG stream IS ACTIVE - received first packet!');
    });
    
    // Wait briefly to see if stream is active
    await Future.delayed(Duration(milliseconds: 100));
    await testSubscription.cancel();
    
    if (!ppgStreamActive) {
      _logger.e('PPG sensor stream is NOT emitting data! Cannot create filter.');
      _logger.e('   This means the sensor configuration did not actually start streaming.');
      _logger.e('   HR/HRV will remain at mock values.');
    }
    
    int ppgPacketCount = 0;
    final ppgFilter = PpgFilterMeditation(
      inputStream: ppgSensor.sensorStream.asyncMap((data) {
        ppgPacketCount++;
        if (ppgPacketCount <= 3) {
          _logger.i(' PPG Packet #$ppgPacketCount received from sensor');
        }
        
        SensorDoubleValue sensorData = data as SensorDoubleValue;
        
        // Safety check for indices
        if (sensorData.values.length < 4) {
             _logger.w('PPG packet has insufficient values! Expected 4, got ${sensorData.values.length}');
             return (sensorData.timestamp, 0.0);
        }
        
        return (
          sensorData.timestamp,
          -(sensorData.values[2] + sensorData.values[3])
        );
      }).asBroadcastStream(),
      sampleFreq: sampleFreq,
      timestampExponent: ppgSensor.timestampExponent,
    );
    
    _logger.i('PPG filter created successfully');
    
    // Listen to heart rate stream
    bool _hrStreamStarted = false;
    _hrSubscription = ppgFilter.heartRateStream.listen((hr) {
      if (!_hrStreamStarted) {
        _logger.i('HR STREAM STARTED! First value: $hr BPM');
        _hrStreamStarted = true;
      }
      
      if (hr.isFinite && hr > 40 && hr < 200) {
        _currentHr = hr; // Update current value
        _hrController.add(hr);
        
        // Add to history
        _hrHistory.add(hr);
        if (_hrHistory.length > _maxHistorySize) {
          _hrHistory.removeAt(0);
        }
        
        // Log every 10th HR value to track data flow
        if (_hrHistory.length % 10 == 0) {
          _logger.d(' HR: $hr BPM (${_hrHistory.length} values collected)');
        }
      } else {
        _logger.w('Invalid HR: $hr BPM (out of range 40-200)');
      }
    }, onError: (error) {
      _logger.e('Error in heart rate stream: $error');
    });
    
    // Listen to RR interval stream for accurate HRV calculation
    bool _rrStreamStarted = false;
    _rrIntervalSubscription = ppgFilter.rrIntervalStream.listen((rrIntervals) {
      if (!_rrStreamStarted) {
        _logger.i(' RR INTERVAL STREAM STARTED! Received ${rrIntervals.length} intervals');
        _rrStreamStarted = true;
      }
      
      // Add to short-term buffer for RMSSD
      _rrIntervals.addAll(rrIntervals);
      
      // Add to long-term buffer for SDNN (keep max 5 minutes)
      _longTermRrIntervals.addAll(rrIntervals);
      if (_longTermRrIntervals.length > _maxLongTermRrIntervals) {
        final excess = _longTermRrIntervals.length - _maxLongTermRrIntervals;
        _longTermRrIntervals.removeRange(0, excess);
      }
      
      // Keep only the last N intervals in short-term buffer (efficient approach)
      if (_rrIntervals.length > _maxRrIntervals) {
        // Remove excess from front efficiently
        final excess = _rrIntervals.length - _maxRrIntervals;
        _rrIntervals.removeRange(0, excess);
      }
      
      // Wait for stable HRV measurements
      if (_rrIntervals.length >= _minRrIntervalsForStableHrv) {
        if (!_hrvIsStable) {
          _hrvIsStable = true;
          _logger.i('HRV measurements now stable (${_rrIntervals.length} intervals collected)');
        }
        _calculateAndEmitHrv();
      } else {
        _logger.d('Collecting RR intervals for HRV (${_rrIntervals.length}/$_minRrIntervalsForStableHrv)');
      }
    }, onError: (error) {
      _logger.e('Error in RR interval stream: $error');
    });
    
    _logger.i('EarableHrSensor started successfully');
  }
  
  
  /// Calculate and emit HRV metrics
  void _calculateAndEmitHrv() {
    if (_rrIntervals.length < _minRrIntervalsForStableHrv) {
      // Not enough data yet for stable measurements
      _logger.d('Not enough RR intervals for stable HRV: ${_rrIntervals.length}/$_minRrIntervalsForStableHrv');
      return;
    }
    
    // Filter artifacts for short-term RMSSD calculation
    final cleanedRR = _filterArtifacts(_rrIntervals);
    
    if (cleanedRR.length < 5) {
      _logger.w('Too many artifacts removed, only ${cleanedRR.length} intervals remain');
      return;
    }
    
    // Calculate RMSSD (always available with short-term data)
    final hrvMetrics = _hrvCalculator.computeTimeHrv(cleanedRR);
    
    // Calculate SDNN if we have enough long-term data (60+ seconds)
    double? sdnnValue;
    if (_longTermRrIntervals.length >= _minRrIntervalsForSdnn) {
      final cleanedLongTerm = _filterArtifacts(_longTermRrIntervals);
      if (cleanedLongTerm.length >= _minRrIntervalsForSdnn) {
        final longTermMetrics = _hrvCalculator.computeTimeHrv(cleanedLongTerm);
        sdnnValue = longTermMetrics['HRV_SDNN'];
        _logger.d('SDNN calculated from ${cleanedLongTerm.length} intervals (${(_longTermRrIntervals.length).toStringAsFixed(0)}s): ${sdnnValue?.toStringAsFixed(1)}ms');
      }
    } else {
      _logger.d('SDNN pending: ${_longTermRrIntervals.length}/$_minRrIntervalsForSdnn intervals (~${_longTermRrIntervals.length}s / need 60s)');
    }
    
    // Emit HRV metrics with SDNN only if available
    final metricsToEmit = Map<String, double>.from(hrvMetrics);
    if (sdnnValue != null && sdnnValue.isFinite) {
      metricsToEmit['HRV_SDNN'] = sdnnValue;
    } else {
      metricsToEmit['HRV_SDNN'] = -1.0; // Signal that SDNN is not yet available
    }
    
    if (hrvMetrics['HRV_RMSSD']!.isFinite) {
      _hrvController.add(metricsToEmit);
      
      // Add to history
      _hrvHistory.add(hrvMetrics['HRV_RMSSD']!);
      if (_hrvHistory.length > _maxHistorySize) {
        _hrvHistory.removeAt(0);
      }
      
      final artifactsRemoved = _rrIntervals.length - cleanedRR.length;
      _logger.d('HRV calculated from ${cleanedRR.length} clean RR intervals (${artifactsRemoved} artifacts removed): '
                'RMSSD=${hrvMetrics['HRV_RMSSD']?.toStringAsFixed(1)}ms, '
                'SDNN=${sdnnValue?.toStringAsFixed(1) ?? "pending"}ms, '
                'Mean=${hrvMetrics['HRV_MEAN']?.toStringAsFixed(1)}ms');
      
      // DEBUG: Print buffer state to verify rotation
      _logger.d('Buffer: ${_rrIntervals.length} raw intervals → ${cleanedRR.length} clean. '
                'First 5 RR: ${cleanedRR.take(5).map((v) => v.toStringAsFixed(1)).join(", ")}, '
                'Last 5 RR: ${cleanedRR.skip(cleanedRR.length - 5).map((v) => v.toStringAsFixed(1)).join(", ")}');
    }
  }
  
  /// Filter artifacts from RR intervals
  /// Removes physiologically impossible values and statistical outliers
  List<double> _filterArtifacts(List<double> rrIntervals) {
    // Step 1: Remove physiologically impossible values
    // Normal HR range: 30-200 BPM → RR range: 300-2000ms
    var filtered = rrIntervals.where((rr) => rr >= 300 && rr <= 2000).toList();
    
    if (filtered.length < 5) return filtered; // Need at least 5 values for statistics
    
    // Step 2: Calculate median
    final sorted = List<double>.from(filtered)..sort();
    final median = sorted[sorted.length ~/ 2];
    
    // Step 3: Remove statistical outliers (>25% deviation from median)
    // Relaxed from 20% to avoid rejecting too many valid beats during initial reading
    final threshold = median * 0.25;
    filtered = filtered.where((rr) => (rr - median).abs() <= threshold).toList();
    
    return filtered;
  }
  
  /// Stop generating real data
  void stop() {
    _isActive = false;
    _hrSubscription?.cancel();
    _hrSubscription = null;
    _rrIntervalSubscription?.cancel();
    _rrIntervalSubscription = null;
    _hrvTimer?.cancel();
    _hrvTimer = null;
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _gyroSubscription?.cancel();
    _gyroSubscription = null;
  }
  
  /// Start IMU sensors for activity detection
  void _startImuSensors() {
    _logger.i('STARTING IMU SENSORS FOR ACTIVITY DETECTION');
    _logger.i('Available sensors: ${sensorManager.sensors.map((s) => s.sensorName).join(", ")}');
    
    try {
      // Find accelerometer sensor
      _logger.d('Looking for accelerometer...');
      final accelSensor = sensorManager.sensors.firstWhere(
        (s) => s.sensorName.toLowerCase() == "accelerometer",
        orElse: () {
          _logger.e('Accelerometer sensor not found - activity detection disabled');
          _logger.d('Available sensors were: ${sensorManager.sensors.map((s) => s.sensorName).join(", ")}');
          throw Exception('Accelerometer not found');
        },
      );
      
      _logger.i('Accelerometer found: ${accelSensor.sensorName}');
      
      // Find gyroscope sensor
      _logger.d('Looking for gyroscope...');
      final gyroSensor = sensorManager.sensors.firstWhere(
        (s) => s.sensorName.toLowerCase() == "gyroscope",
        orElse: () {
          _logger.e('Gyroscope sensor not found - partial activity detection');
          throw Exception('Gyroscope not found');
        },
      );
      
      _logger.i('Gyroscope found: ${gyroSensor.sensorName}');
      
      // Safe frequencies to look for (in order of preference)
      const safeFrequencies = ["30.00", "20.00", "10.00", "50.00"];
      
      // Configure accelerometer
      _logger.d('Configuring accelerometer...');
      bool accelConfigured = false;
      for (final config in accelSensor.relatedConfigurations) {
        _logger.d('  Available config values: ${config.values.length}');
        if (config.values.isNotEmpty) {
           // Look for safe streaming config (30Hz, 20Hz, or 10Hz)
           // IMPORTANT: Must contain "stream" and NOT contain "off"
           dynamic safeConfig;
           for (final freq in safeFrequencies) {
              try {
                safeConfig = config.values.firstWhere((v) {
                  final str = v.toString().toLowerCase();
                  return str.contains(freq) && str.contains('stream') && !str.contains('off');
                });
                if (safeConfig != null) {
                  _logger.i('Found safe accelerometer config: $safeConfig');
                  break;
                }
              } catch (e) {
                _logger.d('  No config matching $freq Hz (stream mode)');
              }
           }
           
           if (safeConfig != null) {
             _logger.i('Setting accelerometer to: $safeConfig');
             config.setConfiguration(safeConfig);
             accelConfigured = true;
             break;
           } else {
              _logger.w(' No SAFE streaming config (30/20/10Hz) found for accelerometer!');
          }
        }
      }
      
      if (!accelConfigured) {
        _logger.e('Failed to configure accelerometer - disabling to prevent crash');
        throw Exception('No safe accelerometer config');
      }
      
      // Configure gyroscope
      _logger.d('Configuring gyroscope...');
      bool gyroConfigured = false;
      for (final config in gyroSensor.relatedConfigurations) {
        _logger.d('  Available config values: ${config.values.length}');
        if (config.values.isNotEmpty) {
           // Look for safe streaming config
           // IMPORTANT: Must contain "stream" and NOT contain "off"
           dynamic safeConfig;
           for (final freq in safeFrequencies) {
              try {
                safeConfig = config.values.firstWhere((v) {
                  final str = v.toString().toLowerCase();
                  return str.contains(freq) && str.contains('stream') && !str.contains('off');
                });
                if (safeConfig != null) {
                  _logger.i('Found safe gyroscope config: $safeConfig');
                  break;
                }
              } catch (e) {
                _logger.d('  No config matching $freq Hz (stream mode)');
              }
           }
           
           if (safeConfig != null) {
             _logger.i('Setting gyroscope to: $safeConfig');
             config.setConfiguration(safeConfig);
             gyroConfigured = true;
             break;
           } else {
              _logger.w(' No SAFE streaming config (30/20/10Hz) found for gyroscope!');
           }
        }
      }
      
      if (!gyroConfigured) {
        _logger.w('Gyroscope not configured - activity detection will be limited');
      }
      
      _logger.i('Subscribing to IMU sensor streams...');
      
      // Subscribe to accelerometer with test logging
      int accelCount = 0;
      _accelSubscription = accelSensor.sensorStream.listen((data) {
        if (data is SensorDoubleValue && data.values.length >= 3) {
          final x = data.values[0];
          final y = data.values[1];
          final z = data.values[2];
          
          accelCount++;
          
          // Log first 5 readings to verify data flow
          if (accelCount <= 5) {
            _logger.i('ACCEL #$accelCount: x=${x.toStringAsFixed(2)}, y=${y.toStringAsFixed(2)}, z=${z.toStringAsFixed(2)} m/s²');
          }
          
          activityDetector.addAccelReading(x, y, z);
          
          // Log activity level every 50 readings to verify detector is working
          if (accelCount % 50 == 0) {
            _logger.d('Activity level after $accelCount accel readings: ${activityDetector.activityLevel.name}');
          }
        }
      }, onError: (error) {
        _logger.e('Accelerometer stream error: $error');
      });
      
      // Subscribe to gyroscope with test logging
      int gyroCount = 0;
      _gyroSubscription = gyroSensor.sensorStream.listen((data) {
        if (data is SensorDoubleValue && data.values.length >= 3) {
          final x = data.values[0];
          final y = data.values[1];
          final z = data.values[2];
          
          gyroCount++;
          
          // Log first 5 readings to verify data flow
          if (gyroCount <= 5) {
            _logger.i('GYRO #$gyroCount: x=${x.toStringAsFixed(2)}, y=${y.toStringAsFixed(2)}, z=${z.toStringAsFixed(2)} rad/s');
          }
          
          activityDetector.addGyroReading(x, y, z);
        }
      }, onError: (error) {
        _logger.e('Gyroscope stream error: $error');
      });
      
      _logger.i('IMU SENSORS SUCCESSFULLY STARTED FOR ACTIVITY DETECTION!');
      
    } catch (e, stackTrace) {
      _logger.e('FAILED TO START IMU SENSORS: $e');
      _logger.e('Stack trace: $stackTrace');
      _logger.e('Activity detection will be unavailable - always reporting "resting"');
    }
  }
  
  /// Explicitly start PPG sensor to ensure data flow
  void _startPpgSensor() {
    _logger.i('Starting PPG sensor configuration...');
    try {
      final config = ppgSensor.relatedConfigurations.firstOrNull;
      if (config == null) {
         _logger.e('No configuration found for PPG sensor!');
         return;
      }
      
      // Attempt to find a suitable value
      dynamic selectedValue;
      try {
        selectedValue = config.values.firstWhere((v) => v is SensorFrequencyConfigurationValue && (v.frequencyHz - sampleFreq).abs() < 1.0);
      } catch (_) {}
      
      if (selectedValue == null && config.values.isNotEmpty) {
        selectedValue = config.values.first;
      }
      
      if (selectedValue != null) {
         _logger.i('Preparing PPG config: $selectedValue');
         
         // Use provider to ensure "Stream" option is enabled if available
         if (configProvider != null && 
             config is ConfigurableSensorConfiguration &&
             config.availableOptions.contains(StreamSensorConfigOption())) {
             
             _logger.i('Enabling Stream Option via Provider');
             configProvider!.addSensorConfigurationOption(config, StreamSensorConfigOption());
             
             // Re-fetch values from provider to ensure consistency
             var providerValues = configProvider!.getSensorConfigurationValues(config, distinct: true);
             if (providerValues.isNotEmpty) {
                // Try to find our selected frequency in the provider's list
                try {
                  var providerSelected = providerValues.firstWhere((v) => v.toString() == selectedValue.toString());
                  selectedValue = providerSelected;
                } catch(e) {
                  // If exact match not found, use first from provider or stick to original
                   if (providerValues.isNotEmpty) selectedValue = providerValues.first;
                }
             }
         }
         
         _logger.i('Setting FINAL PPG config: $selectedValue (Expected Freq: $sampleFreq Hz)');
         config.setConfiguration(selectedValue);
      } else {
         _logger.w('No configuration values found for PPG sensor.');
      }
      
    } catch (e) {
      _logger.e('Error configuring PPG sensor: $e');
    }
  }
  
  /// Get current activity level
  ActivityLevel get activityLevel => activityDetector.activityLevel;
  
  /// Check if user is currently exercising (moderate+ activity)
  bool get isExercising => activityDetector.isExercising;
  
  /// Reset (no-op for real sensor, but kept for interface compatibility)
  @override
  void reset() {
    _rrIntervals.clear();
    _hrvIsStable = false;
  }
  
  /// Dispose resources
  @override
  void dispose() {
    stop();
    _hrController.close();
    _hrvController.close();
    _connectionController.close();
  }
}
