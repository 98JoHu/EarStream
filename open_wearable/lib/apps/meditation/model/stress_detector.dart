/// Stress detector based on HR and HRV metrics
/// 
/// Usage:
/// ```dart
/// final detector = StressDetector();
/// 
/// if (detector.isStressed(95.0, 18.0)) {
///   print('Stress detected!');
/// }
/// 
/// if (detector.isRelaxed(70.0, 45.0)) {
///   print('Relaxed state');
/// }
/// ```
class StressDetector {
  // Default thresholds (can be customized)
  double stressHrThreshold;
  double stressHrvThreshold;
  double relaxHrThreshold;
  double relaxHrvThreshold;
  
  StressDetector({
    this.stressHrThreshold = 95.0,      // BPM (stressed > 95)
    this.stressHrvThreshold = 15.0,     // RMSSD in ms (stressed < 15)
    this.relaxHrThreshold = 75.0,       // BPM (relaxed < 75)
    this.relaxHrvThreshold = 30.0,      // RMSSD in ms (relaxed > 30)
  });
  
  /// Check if stress is detected
  /// 
  /// Stress = High HR OR Low HRV
  bool isStressed(double hr, double hrv) {
    return hr > stressHrThreshold || hrv < stressHrvThreshold;
  }
  
  /// Check if relaxed state is detected
  /// 
  /// Relaxed = Low HR AND High HRV
  bool isRelaxed(double hr, double hrv) {
    return hr < relaxHrThreshold && hrv > relaxHrvThreshold;
  }
  
  /// Get stress level as percentage (0-100)
  /// 
  /// Based on distance from thresholds
  double getStressLevel(double hr, double hrv) {
    // HR contribution (0-50%)
    final hrStress = ((hr - relaxHrThreshold) / (stressHrThreshold - relaxHrThreshold))
        .clamp(0.0, 1.0) * 50;
    
    // HRV contribution (0-50%)
    final hrvStress = ((relaxHrvThreshold - hrv) / (relaxHrvThreshold - stressHrvThreshold))
        .clamp(0.0, 1.0) * 50;
    
    return (hrStress + hrvStress).clamp(0.0, 100.0);
  }
  
  /// Get stress category as string
  /// 
  /// Returns: 'relaxed', 'normal', or 'stressed'
  String getStressCategory(double hr, double hrv) {
    if (isRelaxed(hr, hrv)) {
      return 'relaxed';
    } else if (isStressed(hr, hrv)) {
      return 'stressed';
    } else {
      return 'normal';
    }
  }
}
