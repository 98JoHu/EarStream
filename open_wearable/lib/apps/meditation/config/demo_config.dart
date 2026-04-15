/// Demo Mode Configuration for ACM UbiComp Conference
///
/// This file contains all settings specific to demo mode, which allows
/// quick showcasing of EarStream capabilities without requiring personal
/// user accounts or long calibration periods.

class DemoConfig {
  // ============================================================================
  // DEMO MODE TYPES
  // ============================================================================
  
  /// Demo mode is disabled - use normal app functionality
  static const String modeNone = 'none';
  
  /// Personalized meditation only - 3 segments, no biosignal adaptation
  static const String modePersonalizedOnly = 'personalized_only';
  
  /// Full biosignal-adaptive meditation with shortened calibration
  static const String modeBiosignalAdaptive = 'biosignal_adaptive';
  
  // ============================================================================
  // BIOSIGNAL-ADAPTIVE DEMO SETTINGS
  // ============================================================================
  
  /// Calibration phase duration (filter stabilization, no processing)
  /// Standard would be ~2 minutes, but shortened for demo
  static const Duration calibrationDuration = Duration(seconds: 30);
  
  /// Baseline measurement phase duration
  /// Standard would be 5 minutes, but shortened for demo
  /// This measurement is used as the reference for stress detection
  static const Duration baselineDuration = Duration(seconds: 30);
  
  /// Stress threshold percentage for demo mode
  /// Much lower than normal (typically 25% HR elevation + 40% HRV reduction)
  /// to ensure meditation triggers quickly during demo
  static const double stressThresholdPercent = 3.0; // 3% deviation triggers
  
  /// Maximum monitoring duration before forcing meditation trigger
  /// If stress threshold not met within this time, start meditation anyway
  static const Duration maxMonitoringDuration = Duration(minutes: 2);
  
  /// Stress monitoring check interval during demo
  static const Duration monitoringCheckInterval = Duration(seconds: 3);
  
  // ============================================================================
  // MEDITATION GENERATION SETTINGS
  // ============================================================================
  
  /// Word count per generated segment in demo mode
  /// Standard is 100 words, shortened to 50 for quicker demo experience
  static const int segmentWordCount = 50;
  
  /// Maximum content segments for Personalized Only mode
  /// Does not include beginning/end segments
  static const int personalizedOnlyMaxSegments = 3;
  
  /// Maximum content segments for Biosignal-Adaptive demo mode
  /// Does not include beginning/end segments
  static const int biosignalAdaptiveMaxSegments = 4;
  
  /// Minimum meditation iterations before allowing termination (demo)
  /// Lower than standard to keep demo short
  static const int minMeditationIterations = 1;
  
  // ============================================================================
  // BASELINE MEASUREMENT (NO DEMOGRAPHICS)
  // ============================================================================
  
  /// In demo mode, do NOT use demographic-based baseline estimates
  /// Only use actual measured values from the 30-second baseline period
  /// This makes demo work without personal accounts
  static const bool useDemographicBaseline = false;
  
  /// Fallback baseline HR if measurement fails (BPM)
  /// Used only if baseline measurement produces no valid data
  static const double fallbackBaselineHr = 70.0;
  
  /// Fallback baseline RMSSD if measurement fails (ms)
  /// Used only if baseline measurement produces no valid data
  static const double fallbackBaselineRmssd = 40.0;
  
  // ============================================================================
  // USER PREFERENCES
  // ============================================================================
  
  /// Demo preferences should NOT persist between sessions
  /// Each demo participant sets their own preferences fresh
  static const bool persistPreferences = false;
  
  /// Available meditation styles for demo random selection
  static const List<String> availableStyles = [
    'Mindfulness',
    'Body Scan',
    'Loving-Kindness',
    'Breath Focus',
    'Progressive Relaxation',
  ];
  
  /// Available voice tones for demo random selection
  static const List<String> availableVoiceTones = [
    'Calm',
    'Warm',
    'Gentle',
    'Soothing',
    'Encouraging',
  ];
  
  // ============================================================================
  // DISPLAY SETTINGS
  // ============================================================================
  
  /// Show only current session analytics (no historical/weekly data)
  static const bool showHistoricalData = false;
  
  /// Show only current session in analytics view
  static const bool showOnlyCurrentSession = true;
  
  // ============================================================================
  // DEMO PHASE DISPLAY MESSAGES
  // ============================================================================
  
  static String get calibrationMessage => 
      'Calibration Phase\n\nFilters are adjusting to your signal.\nPlease remain still and relaxed.\n\n${calibrationDuration.inSeconds} seconds...';
  
  static String get baselineMessage => 
      'Baseline Measurement\n\nEstablishing your resting heart rate and HRV.\nThis will be your reference point.\n\n${baselineDuration.inSeconds} seconds...';
  
  static String get monitoringMessage => 
      'Monitoring Stress Level\n\nTracking your biosignals in real-time.\nMeditation will begin when needed.\n\nThreshold: ${stressThresholdPercent}% deviation';
  
  static const String sealCheckMessage =
      'Seal Check\n\nPlease ensure the earable fits properly for accurate readings.\nYou can retry the seal check as many times as needed.';
  
  // ============================================================================
  // HELPER METHODS
  // ============================================================================
  
  /// Get random meditation style for "Surprise me" feature
  static String getRandomStyle() {
    return availableStyles[
      DateTime.now().millisecond % availableStyles.length
    ];
  }
  
  /// Get random voice tone for "Surprise me" feature
  static String getRandomVoiceTone() {
    return availableVoiceTones[
      DateTime.now().millisecond % availableVoiceTones.length
    ];
  }
  
  /// Calculate expected baseline sample count at 200Hz
  static int getExpectedBaselineSamples() {
    return (baselineDuration.inSeconds * 200).round();
  }
  
  /// Calculate expected calibration sample count at 200Hz
  static int getExpectedCalibrationSamples() {
    return (calibrationDuration.inSeconds * 200).round();
  }
  
  /// Get segment word count based on demo mode
  static int getSegmentWordCount(String demoMode) {
    if (demoMode == modePersonalizedOnly || 
        demoMode == modeBiosignalAdaptive) {
      return segmentWordCount;
    }
    return 100; // Standard length for non-demo modes
  }
  
  /// Get max segments based on demo mode
  static int getMaxSegments(String demoMode) {
    switch (demoMode) {
      case modePersonalizedOnly:
        return personalizedOnlyMaxSegments;
      case modeBiosignalAdaptive:
        return biosignalAdaptiveMaxSegments;
      default:
        return 10; // Standard max for non-demo modes
    }
  }
  
  /// Debug summary of demo configuration
  static String getConfigSummary(String demoMode) {
    if (demoMode == modeNone) {
      return 'Demo mode is disabled';
    }
    
    final buffer = StringBuffer();
    buffer.writeln('=== Demo Mode Configuration ===');
    buffer.writeln('Mode: $demoMode');
    
    if (demoMode == modeBiosignalAdaptive) {
      buffer.writeln('Calibration: ${calibrationDuration.inSeconds}s');
      buffer.writeln('Baseline: ${baselineDuration.inSeconds}s');
      buffer.writeln('Stress Threshold: ${stressThresholdPercent}%');
      buffer.writeln('Max Monitoring: ${maxMonitoringDuration.inMinutes} min');
    }
    
    buffer.writeln('Segment Length: $segmentWordCount words');
    buffer.writeln('Max Segments: ${getMaxSegments(demoMode)}');
    buffer.writeln('Persist Preferences: $persistPreferences');
    buffer.writeln('==============================');
    
    return buffer.toString();
  }
}

/// Demo phase enumeration for biosignal-adaptive mode
enum DemoPhase {
  /// Not in demo mode
  none,
  
  /// Selecting demo sub-mode (Personalized vs Biosignal-Adaptive)
  modeSelection,
  
  /// Setting meditation preferences (Personalized Only mode)
  settingPreferences,
  
  /// Performing seal check (Biosignal-Adaptive mode)
  sealCheck,
  
  /// Calibration phase - filters adjusting (Biosignal-Adaptive mode)
  calibration,
  
  /// Baseline measurement phase (Biosignal-Adaptive mode)
  baselineMeasurement,
  
  /// Stress monitoring phase (Biosignal-Adaptive mode)
  monitoring,
  
  /// Active meditation session
  meditationSession,
  
  /// Showing analytics after session
  analytics,
  
  /// Demo completed, returning to selection
  completed,
}

/// Demo preferences for Personalized Only mode
class DemoMeditationPreferences {
  final String meditationStyle;
  final String voiceTone;
  final int durationMinutes;
  final bool useBackgroundSounds;
  
  const DemoMeditationPreferences({
    required this.meditationStyle,
    required this.voiceTone,
    required this.durationMinutes,
    required this.useBackgroundSounds,
  });
  
  /// Create random preferences for "Surprise me" feature
  factory DemoMeditationPreferences.random() {
    final now = DateTime.now();
    return DemoMeditationPreferences(
      meditationStyle: DemoConfig.getRandomStyle(),
      voiceTone: DemoConfig.getRandomVoiceTone(),
      durationMinutes: 5 + (now.second % 6), // 5-10 minutes
      useBackgroundSounds: now.millisecond % 2 == 0,
    );
  }
  
  /// Create default preferences
  factory DemoMeditationPreferences.defaults() {
    return const DemoMeditationPreferences(
      meditationStyle: 'Mindfulness',
      voiceTone: 'Calm',
      durationMinutes: 5,
      useBackgroundSounds: true,
    );
  }
  
  @override
  String toString() {
    return 'Style: $meditationStyle, Tone: $voiceTone, Duration: $durationMinutes min, Sounds: $useBackgroundSounds';
  }
}
