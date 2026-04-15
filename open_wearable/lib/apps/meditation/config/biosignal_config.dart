/// Biosignal Processing Configuration for EarStreAM
///
/// This file centralizes all parameters for PPG signal processing,
/// HRV calculation, and stress detection to improve code maintainability
/// and facilitate academic documentation.

class BiosignalConfig {
  // ============================================================================
  // PPG SENSOR CONFIGURATION
  // ============================================================================
  
  /// PPG sampling frequency in Hz
  /// Research standard for accurate HRV: ≥200 Hz
  /// Lower frequencies (30-100 Hz) acceptable for HR only
  static const double ppgSamplingFrequency = 200.0; // Hz
  
  /// Fallback sampling frequency if 200 Hz not available
  static const double ppgFallbackFrequency = 100.0; // Hz
  
  // ============================================================================
  // SIGNAL PROCESSING - BAND-PASS FILTER
  // ============================================================================
  
  /// Low-cut frequency for band-pass filter (Hz)
  /// Removes baseline drift and very slow oscillations
  /// Formula: 60 BPM / 60 seconds = 1 Hz, so 0.5 Hz = 30 BPM lower bound
  static const double bandPassLowCut = 0.5; // Hz (~30 BPM)
  
  /// High-cut frequency for band-pass filter (Hz)
  /// Removes high-frequency noise and motion artifacts
  /// Formula: 240 BPM / 60 seconds = 4 Hz upper bound
  static const double bandPassHighCut = 4.0; // Hz (~240 BPM)
  
  // ============================================================================
  // PEAK DETECTION
  // ============================================================================
  
  /// Minimum prominence for PPG peak detection (normalized units)
  /// Peaks must be this much higher than surrounding valleys
  static const double minPeakProminence = 0.1;
  
  /// Minimum distance between peaks in milliseconds
  /// Prevents double-counting; 300ms = max ~200 BPM
  static const int minPeakDistanceMs = 300; // ms
  
  /// Sliding window duration for peak detection
  static const int peakDetectionWindowSeconds = 8; // seconds
  
  /// Smoothing radius for peak detection (number of samples)
  static const int peakSmoothingRadius = 4; // samples
  
  // ============================================================================
  // HEART RATE CALCULATION
  // ============================================================================
  
  /// Kalman filter process noise for HR smoothing
  /// Lower = more stable but slower response to changes
  static const double hrKalmanProcessNoise = 0.01; // Q
  
  /// Kalman filter measurement noise for HR smoothing  
  /// Higher = trust measurements less, smoother output
  static const double hrKalmanMeasurementNoise = 4.0; // R
  
  /// Valid heart rate range (BPM)
  static const double minValidHeartRate = 30.0; // BPM
  static const double maxValidHeartRate = 220.0; // BPM
  
  // ============================================================================
  // HRV CALCULATION - RR INTERVAL BUFFERS
  // ============================================================================
  
  /// Time window for RMSSD calculation
  /// Research standard: 5 minutes for reliable parasympathetic assessment
  /// RMSSD is calculated on ALL RR intervals within this sliding time window
  /// (not a fixed interval count)
  static const Duration rmssdCalculationWindow = Duration(minutes: 5);
  
  /// Minimum measurement time before calculating RMSSD
  /// Prevents unreliable stress detection with insufficient data
  /// RMSSD will NOT be calculated until this duration has elapsed
  static const Duration rmssdMinimumMeasurementTime = Duration(minutes: 1);
  
  /// Maximum number of RR intervals for short-term buffer (RMSSD)
  /// NOTE: This is now used as a safety limit, actual RMSSD uses time-based windowing
  /// At 60 BPM: 5 minutes ≈ 300 beats
  /// At 80 BPM: 5 minutes ≈ 400 beats
  /// Set to 400 to accommodate higher heart rates
  static const int maxShortTermRrIntervals = 400; // beats (~5 min at 80 BPM)
  
  /// Minimum RR intervals for initial RMSSD calculation
  /// NOTE: This is deprecated - now using time-based minimum (1 minute)
  /// Kept for compatibility with other code
  @Deprecated('Use rmssdMinimumMeasurementTime instead')
  static const int minRrIntervalsForInitialRmssd = 10; // beats
  
  /// Maximum number of RR intervals for long-term buffer (SDNN)  
  /// For 5-minute SDNN calculation (clinical standard)
  static const int maxLongTermRrIntervals = 400; // beats (~5 min at 80 BPM)
  
  /// Minimum RR intervals for SDNN calculation
  /// Research standard: 30+ intervals from ≥1 minute recording
  static const int minRrIntervalsForSdnn = 30; // beats
  
  // ============================================================================
  // ARTIFACT FILTERING
  // ============================================================================
  
  /// Physiological RR interval range (milliseconds)
  /// Based on 30-200 BPM normal human heart rate range
  /// 30 BPM = 2000 ms, 200 BPM = 300 ms
  static const double minPhysiologicalRrInterval = 300.0; // ms (200 BPM max)
  static const double maxPhysiologicalRrInterval = 2000.0; // ms (30 BPM min)
  
  /// Maximum successive RR interval difference (milliseconds)
  /// Rapid HR changes >300 ms between beats indicate artifacts
  /// Protects against motion-induced false peaks
  static const double maxSuccessiveRrDifference = 300.0; // ms
  
  /// Statistical outlier threshold (percentage from median)
  /// Removes RR intervals deviating >25% from local median
  /// Relaxed from 20% to avoid over-filtering during arrhythmia
  static const double outlierDeviationThreshold = 0.25; // 25%
  
  /// Minimum RR intervals needed for statistical outlier removal
  /// Need at least 5 values to calculate meaningful median
  static const int minRrIntervalsForOutlierRemoval = 5; // beats
  
  // ============================================================================
  // BASELINE ESTABLISHMENT
  // ============================================================================
  
  /// Calibration duration for adaptive baseline refinement
  /// Live measurements integrate with research-based estimates over this period
  static const Duration baselineCalibrationDuration = Duration(minutes: 5);
  
  /// Initial trust weight for research-based baseline
  /// 0.8 = 80% research, 20% measured at calibration start
  static const double initialResearchWeight = 0.8;
  
  /// Final trust weight for research-based baseline after calibration
  /// 0.3 = 30% research, 70% measured after 5 minutes
  static const double finalResearchWeight = 0.3;
  
  // ============================================================================
  // STRESS DETECTION THRESHOLDS
  // ============================================================================
  
  /// HR threshold multiplier for stress detection
  /// Stress detected when: current HR > baseline × 1.25 (25% elevation)
  static const double stressHrMultiplier = 1.25;
  
  /// HRV threshold multiplier for stress detection  
  /// Stress detected when: current HRV < baseline × 0.60 (40% reduction)
  static const double stressHrvMultiplier = 0.60;
  
  /// HR threshold multiplier for relaxed state
  /// Relaxed when: current HR < baseline × 1.04 (within 4% of baseline)
  static const double relaxedHrMultiplier = 1.04;
  
  /// HRV threshold multiplier for relaxed state
  /// Relaxed when: current HRV > baseline × 1.20 (20% increase)
  static const double relaxedHrvMultiplier = 1.20;
  
  /// Stress monitoring polling interval
  /// How often to check stress state during idle monitoring
  static const Duration stressMonitoringInterval = Duration(seconds: 3);
  
  // ============================================================================
  // MEDITATION SESSION TERMINATION
  // ============================================================================
  
  /// Minimum meditation iterations before allowing termination
  /// Prevents premature ending after just 1-2 segments
  static const int minMeditationIterations = 2;
  
  /// Maximum meditation iterations (safety limit)
  /// Ensures session eventually ends even if relaxation not achieved
  static const int maxMeditationIterations = 10;
  
  /// HRV improvement thresholds for termination scenarios
  /// Percentage improvement from baseline required to end session
  static const double hrvImprovementExcellent = 0.30; // 30%
  static const double hrvImprovementStrong = 0.25; // 25%  
  static const double hrvImprovementGood = 0.20; // 20%
  static const double hrvImprovementMild = 0.10; // 10%
  
  /// HR improvement threshold for combined termination
  /// Used in scenario 4: both HR and HRV must improve
  static const double hrImprovementThreshold = 0.10; // 10%
  
  /// Stress level thresholds for termination (0-100 scale)
  static const double stressLevelLow = 40.0; // <40% stress
  static const double stressLevelVeryLow = 30.0; // <30% stress
  static const double stressLevelMinimal = 20.0; // <20% stress
  
  /// Sensor timeout duration
  /// Stop session if no sensor data received for this long
  static const Duration sensorTimeoutDuration = Duration(seconds: 45);
  
  // ============================================================================
  // ACTIVITY DETECTION (IMU)
  // ============================================================================
  
  /// Accelerometer threshold for resting state (g-units)
  /// Below this = no significant movement detected
  /// Earables detect head bobbing, so threshold higher than wrist devices
  static const double restingAccelerometerThreshold = 0.20; // g
  
  /// Gyroscope threshold for resting state (degrees/second)
  /// Below this = no significant head rotation
  /// Allows normal looking around without triggering activity
  static const double restingGyroscopeThreshold = 300.0; // deg/s
  
  /// Moderate activity accelerometer threshold (g-units)
  /// Above this = exercise likely, suppress stress detection
  static const double moderateAccelerometerThreshold = 0.40; // g
  
  /// Moderate activity gyroscope threshold (degrees/second)
  /// Above this = active movement, suppress stress detection
  static const double moderateGyroscopeThreshold = 450.0; // deg/s
  
  /// Activity classification window size (number of samples)
  /// Moving average over ~3 seconds at 10 Hz sample rate
  static const int activityWindowSize = 30; // samples
  
  // ============================================================================
  // DISPLAY AND HISTORY
  // ============================================================================
  
  /// Maximum entries in HR/HRV history for charts
  /// 3600 samples at 1/second = 1 hour of data
  static const int maxHistorySize = 3600;
  
  // ============================================================================
  // HELPER METHODS
  // ============================================================================
  
  /// Calculate expected number of RR intervals for a given duration at a specific heart rate
  /// Example: At 70 BPM, 5 minutes = 70 × 5 = 350 beats
  static int expectedBeatsForDuration(Duration duration, double heartRateBpm) {
    final minutes = duration.inSeconds / 60.0;
    return (heartRateBpm * minutes).ceil();
  }
  
  /// Check if RMSSD measurement is stable (past minimum time threshold)
  static bool isRmssdStable(Duration measurementDuration) {
    return measurementDuration >= rmssdMinimumStableTime;
  }
  
  /// Get weighted research baseline during calibration
  /// Returns weight that decreases linearly from initialResearchWeight to finalResearchWeight
  static double getResearchWeightForElapsedTime(Duration elapsed) {
    if (elapsed >= baselineCalibrationDuration) {
      return finalResearchWeight;
    }
    
    final progress = elapsed.inMilliseconds / baselineCalibrationDuration.inMilliseconds;
    return initialResearchWeight - (progress * (initialResearchWeight - finalResearchWeight));
  }
  
  /// Debug summary of current configuration
  static String getConfigSummary() {
    return '''
    === EarStreAM Biosignal Configuration ===
    PPG Sampling: $ppgSamplingFrequency Hz
    Band-pass Filter: $bandPassLowCut - $bandPassHighCut Hz
    RMSSD Window: ${rmssdCalculationWindow.inMinutes} min (${maxShortTermRrIntervals} beats max)
    RMSSD Stable After: ${rmssdMinimumStableTime.inSeconds} sec
    SDNN Window: ${maxLongTermRrIntervals} beats
    Baseline Calibration: ${baselineCalibrationDuration.inSeconds} sec
    Stress HR Threshold: baseline × $stressHrMultiplier
    Stress HRV Threshold: baseline × $stressHrvMultiplier
    Activity Window: $activityWindowSize samples (~${activityWindowSize / 10} sec at 10 Hz)
    =========================================
    ''';
  }
}
