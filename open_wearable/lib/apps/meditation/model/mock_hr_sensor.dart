import 'dart:async';
import 'dart:math';
import 'hr_sensor_interface.dart';

/// Mock sensor that simulates realistic HR/HRV data for testing without hardware.
/// 
/// Usage:
/// ```dart
/// final sensor = MockHrSensor();
/// sensor.hrStream.listen((hr) => print('HR: $hr BPM'));
/// sensor.hrvStream.listen((hrv) => print('HRV RMSSD: $hrv ms'));
/// 
/// // Simulate stress
/// sensor.simulateStress();
/// 
/// // Simulate relaxation
/// sensor.simulateRelaxation();
/// ```
class MockHrSensor implements HrSensorInterface {
  final StreamController<double> _hrController = StreamController<double>.broadcast();
  final StreamController<Map<String, double>> _hrvController = StreamController<Map<String, double>>.broadcast();
  
  Timer? _timer;
  double _currentHr = 75.0; // Baseline heart rate
  double _currentHrv = 120.0; // Baseline HRV (RMSSD) - realistic value
  double _targetHr = 75.0;
  double _targetHrv = 120.0;
  bool _isActive = false;
  
  final Random _random = Random();
  
  /// Stream of heart rate values in BPM
  Stream<double> get hrStream => _hrController.stream;
  
  /// Stream of HRV metrics (SDNN, RMSSD, pNN50)
  Stream<Map<String, double>> get hrvStream => _hrvController.stream;
  
  /// Stream of connection state (always connected for mock)
  Stream<bool> get isConnected => Stream.value(true).asBroadcastStream();
  
  /// Start generating mock data
  Future<void> start() async {
    if (_isActive) return;
    _isActive = true;
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Gradually move towards target HR and HRV (very fast for testing)
      _currentHr += (_targetHr - _currentHr) * 0.95; // Super fast: 95% per second
      _currentHrv += (_targetHrv - _currentHrv) * 0.95; // Super fast: 95% per second
      
      // Add realistic noise
      final hrNoise = _random.nextDouble() * 4 - 2; // +/- 2 BPM
      final hr = (_currentHr + hrNoise).clamp(50.0, 120.0);
      
      final hrvNoise = _random.nextDouble() * 3 - 1.5; // +/- 1.5 ms (smaller noise)
      final rmssd = (_currentHrv + hrvNoise).clamp(10.0, 200.0);
      
      _hrController.add(hr);
      
      // Generate mock HRV data with realistic values matching real sensor
      // SDNN is typically 2.5-3x lower than RMSSD
      _hrvController.add({
        'HRV_SDNN': rmssd / 2.7,  // SDNN: if RMSSD=120ms -> SDNN≈44ms (realistic!)
        'HRV_RMSSD': rmssd,       // RMSSD
        'HRV_pNN50': (rmssd / 3).clamp(0.0, 60.0), // pNN50 correlates with HRV
      });
    });
  }
  
  /// Stop generating mock data
  void stop() {
    _isActive = false;
    _timer?.cancel();
    _timer = null;
  }
  
  /// Simulate stress (increase HR, decrease HRV)
  /// Triggers stress detection: HR > 95 OR HRV < 15
  void simulateStress() {
    _targetHr = 100.0;  // Well above 95 threshold
    _targetHrv = 12.0;  // Below 15ms threshold - THIS TRIGGERS STRESS!
  }
  
  /// Simulate relaxation (decrease HR, increase HRV)
  /// Triggers relaxation detection: HR < 75 AND HRV > 30
  void simulateRelaxation() {
    _targetHr = 65.0;   // Well below 75 threshold
    _targetHrv = 150.0; // High HRV indicates relaxation
  }
  
  /// Reset to baseline
  void reset() {
    _targetHr = 75.0;   // Normal resting HR
    _targetHrv = 120.0; // Good HRV
  }
  
  /// Dispose resources
  void dispose() {
    stop();
    _hrController.close();
    _hrvController.close();
  }
}
