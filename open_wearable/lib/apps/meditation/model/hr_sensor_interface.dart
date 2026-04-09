import 'dart:async';

/// Interface for HR/HRV sensors (mock or real)
abstract class HrSensorInterface {
  /// Stream of heart rate values in BPM
  Stream<double> get hrStream;
  
  /// Stream of HRV metrics (SDNN, RMSSD, pNN50)
  Stream<Map<String, double>> get hrvStream;
  
  /// Stream of connection state (true=connected, false=disconnected)
  Stream<bool> get isConnected;
  
  /// Start generating data
  Future<void> start();
  
  /// Stop generating data
  void stop();
  
  /// Reset to baseline (mock only, no-op for real)
  void reset();
  
  /// Dispose resources
  void dispose();
}
