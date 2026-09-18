import 'meditation_prompt_policy.dart';

enum BaselineComputationMode {
  profileBlended,
  physiologicalOnly,
}

class BioAdaptiveSessionConfig {
  final bool includeCalibration;
  final Duration calibrationDuration;
  final Duration baselineDuration;
  final BaselineComputationMode baselineComputationMode;
  final double? stressThresholdOverride;
  final Duration? meditationSegmentDuration;
  final Duration? hrvMinimumWindow;
  final Duration? metricWindowDuration;

  /// Allows physiologically plausible, beat-derived estimates that fall below
  /// the production stream's confidence threshold. Used only by the
  /// time-constrained conference demo; it never introduces synthetic values.
  final bool useBestEffortEstimates;
  final MeditationPromptPolicy promptPolicy;
  final bool allowStressSimulation;

  const BioAdaptiveSessionConfig({
    required this.includeCalibration,
    required this.calibrationDuration,
    required this.baselineDuration,
    required this.baselineComputationMode,
    required this.stressThresholdOverride,
    required this.meditationSegmentDuration,
    required this.hrvMinimumWindow,
    required this.metricWindowDuration,
    required this.useBestEffortEstimates,
    required this.promptPolicy,
    required this.allowStressSimulation,
  });

  /// Full-length production behaviour. It uses the same sensor-only baseline
  /// path as the demo, but retains the longer production timing and stricter
  /// signal-quality requirements.
  static const standard = BioAdaptiveSessionConfig(
    includeCalibration: true,
    calibrationDuration: Duration(seconds: 30),
    baselineDuration: Duration(minutes: 5),
    baselineComputationMode: BaselineComputationMode.physiologicalOnly,
    stressThresholdOverride: null,
    meditationSegmentDuration: null,
    hrvMinimumWindow: null,
    metricWindowDuration: null,
    useBestEffortEstimates: false,
    promptPolicy: MeditationPromptPolicy.standard,
    allowStressSimulation: true,
  );

  /// Time-condensed conference cycle described in the demo paper.
  static const conferenceDemo = BioAdaptiveSessionConfig(
    includeCalibration: true,
    calibrationDuration: Duration(seconds: 30),
    baselineDuration: Duration(seconds: 30),
    baselineComputationMode: BaselineComputationMode.physiologicalOnly,
    stressThresholdOverride: 0.03,
    meditationSegmentDuration: Duration(seconds: 30),
    hrvMinimumWindow: Duration(seconds: 30),
    metricWindowDuration: Duration(seconds: 30),
    useBestEffortEstimates: true,
    promptPolicy: MeditationPromptPolicy.conferenceDemo,
    allowStressSimulation: false,
  );
}
