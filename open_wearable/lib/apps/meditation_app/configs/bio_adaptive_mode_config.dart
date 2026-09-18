import 'overall_config.dart';

/// Baseline calculation strategies supported by biosignal-adaptive sessions.
enum BaselineComputationMode {
  profileBlended,
  physiologicalOnly,
}

/// Parameters used by the regular biosignal-adaptive mode.
abstract final class BioAdaptiveModeConfig {
  // Session phases and intervention.
  static const int meditationSegmentCount = 10;
  static const bool includeCalibration = true;
  static const Duration calibrationDuration = Duration(seconds: 30);
  static const Duration baselineDuration = Duration(minutes: 5);
  static const BaselineComputationMode baselineComputationMode =
      BaselineComputationMode.physiologicalOnly;
  static const double? stressThresholdOverride = null;
  // Null keeps regular segments narration-driven instead of applying the
  // demo's 30-second target.
  static const Duration? meditationSegmentDurationOverride = null;
  static const int promptApproximateWordsPerSegment =
      OverallMeditationConfig.standardPromptApproximateWordsPerSegment;
  static const Duration? guaranteedMeditationDelay = null;
  static const bool useBestEffortEstimates = false;
  static const bool allowStressSimulation = true;

  // Production HR/HRV windows. Null delegates to HrHrvProcessor's defaults:
  // 10 s HR buffer, 4 s metric eligibility, 60 s minimum RMSSD history, and
  // 5 min maximum RMSSD history.
  static const Duration? hrvMinimumWindowOverride = null;
  static const Duration? metricWindowDurationOverride = null;

  static const double defaultHeartRateWindowSeconds = 10;
  static const double defaultMetricEligibilityWindowSeconds = 4;
  static const double defaultHrvHistoryWindowSeconds = 300;
  static const Duration defaultHrvMinimumWindow = Duration(seconds: 60);
  static const Duration processorWarmupDuration = Duration(seconds: 10);
  static const Duration metricEmitInterval = Duration(seconds: 3);
  static const Duration phaseProgressUpdateInterval =
      Duration(milliseconds: 100);

  // Requested sensor stream rates and fallbacks when metadata is unavailable.
  static const int ppgTargetFrequencyHz = 200;
  static const double ppgFallbackFrequencyHz = 100;
  static const int accelerometerTargetFrequencyHz = 100;
  static const double accelerometerFallbackFrequencyHz = 100;
  static const int gyroscopeTargetFrequencyHz = 100;
  static const double gyroscopeFallbackFrequencyHz = 100;

  static const Duration chartVisibleWindow = Duration(minutes: 1);

  // Physical-activity classification and stress-suppression policy.
  static const double gravityMetersPerSecondSquared = 9.81;
  static const double restingAccelerationThreshold = 0.2;
  static const double restingGyroscopeThreshold = 300;
  static const double lightAccelerationThreshold = 0.4;
  static const double lightGyroscopeThreshold = 600;
  static const double moderateAccelerationThreshold = 0.8;
  static const double moderateGyroscopeThreshold = 1200;
  static const double vigorousAccelerationThreshold = 2;
  static const double vigorousGyroscopeThreshold = 3000;
  static const Duration activityClassificationInterval = Duration(seconds: 3);
  static const Duration activityHistoryWindow = Duration(minutes: 5);
  static const double lightActivitySuppressionRatio = 0.4;
  static const double moderateActivitySuppressionRatio = 0.2;
  static const double vigorousActivitySuppressionRatio = 0.05;
  static const double intenseActivitySuppressionRatio = 0.02;

  // Recording-derived stress playback used by the regular mode only.
  static const Duration recordedStressSampleInterval = Duration(seconds: 1);
  static const double recordedStressBaselineHeartRate = 71;
  static const double recordedStressBaselineRmssd = 80;
  static const double recordedStressBuildUpHeartRate = 80;
  static const double recordedStressBuildUpRmssd = 50;
  static const double recordedStressPeakHeartRate = 97;
  static const double recordedStressPeakRmssd = 12;
  static const double recordedStressBuildUpEndSeconds = 90;
  static const double recordedStressSpikeEndSeconds = 120;
  static const int recordedStressDetectionHeartRate = 90;
  static const double recordedStressDetectionRmssd = 40;
  static const double recordedStressOuAlpha = 0.9672;
  static const double recordedStressHrOuSigmaStep = 0.763;

  // Recovery begins when stress playback triggers a meditation.
  static const double relaxationTargetHeartRate = 62;
  static const double relaxationTargetRmssd = 90;
  static const double relaxationDurationSeconds = 360;
}
