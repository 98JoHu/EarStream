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
    required this.promptPolicy,
    required this.allowStressSimulation,
  });

  /// Existing production behaviour. Keeping this as the default makes the
  /// demo configuration additive rather than a second implementation.
  static const standard = BioAdaptiveSessionConfig(
    includeCalibration: true,
    calibrationDuration: Duration(seconds: 30),
    baselineDuration: Duration(minutes: 5),
    baselineComputationMode: BaselineComputationMode.profileBlended,
    stressThresholdOverride: null,
    meditationSegmentDuration: null,
    hrvMinimumWindow: null,
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
    hrvMinimumWindow: Duration(seconds: 15),
    promptPolicy: MeditationPromptPolicy.conferenceDemo,
    allowStressSimulation: false,
  );
}
