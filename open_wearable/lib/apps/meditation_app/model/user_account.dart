import 'dart:math';

import '../widgets/emojis.dart';

enum Gender {
  male(
    label: "Male",
    emoji: AppEmojis.male,
  ),
  female(
    label: "Female",
    emoji: AppEmojis.female,
  ),
  nonBinary(
    label: "Non-Binary",
  ),
  unspecified(
    label: "Unspecified",
  );

  final String label;
  final String? emoji;

  const Gender({
    required this.label,
    this.emoji,
  });
}

enum SpeakingSpeed {
  verySlow(
    label: "Very Slow",
    isRecommended: false,
    emoji: AppEmojis.snail,
    speed: 0.2,
  ),
  slow(
    label: "Slow",
    isRecommended: true,
    emoji: AppEmojis.turtle,
    speed: 0.3,
  ),
  medium(
    label: "Medium",
    isRecommended: false,
    emoji: AppEmojis.walkingPerson,
    speed: 0.5,
  ),
  fast(
    label: "Fast",
    isRecommended: false,
    emoji: AppEmojis.runningPerson,
    speed: 0.7,
  );

  final String label;
  final String emoji;
  final bool isRecommended;
  // flutter_tts speech rate, on its normalized 0.0-1.0 scale.
  final double speed;
  const SpeakingSpeed({
    required this.label,
    required this.emoji,
    required this.speed,
    required this.isRecommended,
  });
}

enum FitnessLevel { sedentary, moderate, active, athlete }

enum MeditationEnvironment {
  nature(
    label: "Peaceful Nature",
    emoji: AppEmojis.tree,
    assetPath: "Peaceful_Nature.wav",
  ),
  ocean(
    label: "Ocean beach",
    emoji: AppEmojis.wave,
    assetPath: "Ocean_Beach.wav",
  ),
  mountain(
    label: "Mountain",
    emoji: AppEmojis.mountain,
    assetPath: "Mountain.wav",
  ),
  forest(
    label: "Forest",
    emoji: AppEmojis.forest,
    assetPath: "Forest.wav",
  ),
  garden(
    label: "Garden",
    emoji: AppEmojis.cherryBlossom,
    assetPath: "Garden.mp3",
  );

  final String label;
  final String emoji;
  final String assetPath;
  const MeditationEnvironment({
    required this.label,
    required this.emoji,
    required this.assetPath,
  });
}

enum MeditationType {
  mindfulness(
    label: "Mindfulness",
    emoji: AppEmojis.meditatingPerson,
  ),
  breathing(
    label: "Breathing",
    emoji: AppEmojis.breathing,
  ),
  bodyScan(
    label: "Body Scan",
    emoji: AppEmojis.bodyScan,
  ),
  visualizationJourney(
    label: "Visualization Journey",
    emoji: AppEmojis.visualizationJourney,
  );

  final String label;
  final String emoji;
  const MeditationType({required this.label, required this.emoji});
}

class UserAccount {
  // Basic user information
  String? username;
  String? firstName;
  String? lastName;
  Gender? gender;
  int? age;
  FitnessLevel? fitnessLevel;

  // Meditation preferences
  Gender? voiceGender;
  SpeakingSpeed? speakingSpeed;
  MeditationType? meditationType;
  MeditationEnvironment? meditationEnvironment;
  String? additionalPreferences;
  double? stressThreshold;

  // API keys and tokens
  String? outlookSuppressionToken;
  String? deepseekApiKey;
  bool hasValidDeepseekKey = false;
  String? elevenLabsApiKey;
  bool hasValidElevenLabsKey = false;
  // Populated by ElevenLabsManager.updateUser() once the key is verified.
  String? elevenLabsVoiceId;
  List<({String voice, String id})>? availableElevenLabsVoices;
  String? dashscopeApiKey;
  bool hasValidDashscopeKey = false;

  // Bio-adaptive meditation settings
  int? baselineHeartRate;
  double? baselineRMSSD;

  UserAccount({
    this.username,
    this.firstName,
    this.lastName,
    this.gender,
    this.age,
    this.fitnessLevel,
    this.voiceGender,
    this.speakingSpeed,
    this.meditationType,
    this.meditationEnvironment,
    this.additionalPreferences,
    this.stressThreshold,
    this.outlookSuppressionToken,
    this.deepseekApiKey,
    this.elevenLabsApiKey,
    this.dashscopeApiKey,
    this.baselineHeartRate,
    this.baselineRMSSD,
  });

  (int, double) get baselineBiometrics {
    // if values have been determined return them
    if (baselineHeartRate != null && baselineRMSSD != null) {
      return (baselineHeartRate!, baselineRMSSD!);
    }

    // refer to the default values if not set
    int defaultHeartRate = 72;
    double defaultRMSSD = 42.0;

    // Age adjustment for baseline values
    if (age != null) {
      if (age! < 25) {
        defaultHeartRate = 68;
        defaultRMSSD = 50.0;
      } else if (age! < 35) {
        defaultHeartRate = 70;
        defaultRMSSD = 42.0;
      } else if (age! < 45) {
        defaultHeartRate = 72;
        defaultRMSSD = 35.0;
      } else if (age! < 55) {
        defaultHeartRate = 74;
        defaultRMSSD = 28.0;
      } else if (age! < 65) {
        defaultHeartRate = 76;
        defaultRMSSD = 22.0;
      } else {
        defaultHeartRate = 78;
        defaultRMSSD = 18.0;
      }
    }

    // Gender adjustment for baseline values
    if (gender != null) {
      switch (gender!) {
        case Gender.male:
          defaultHeartRate -= 4;
          defaultRMSSD += 6.0;
          break;
        case Gender.female:
          defaultHeartRate += 4;
          defaultRMSSD -= 6.0;
          break;
        default:
          // No change for unspecified
          break;
      }
    }

    // Fitness level adjustment for baseline values
    if (fitnessLevel != null) {
      switch (fitnessLevel!) {
        case FitnessLevel.sedentary:
          defaultHeartRate += 8;
          defaultRMSSD -= 12.0;
          break;
        case FitnessLevel.moderate:
          // No change for moderate fitness level
          break;
        case FitnessLevel.active:
          defaultHeartRate -= 6;
          defaultRMSSD += 15.0;
          break;
        case FitnessLevel.athlete:
          defaultHeartRate -= 12;
          defaultRMSSD += 35.0;
          break;
      }
    }
    // The age/gender/fitness adjustments are additive, so the unlucky
    // combinations bottom out at or below zero — an over-65 sedentary woman
    // lands on exactly 0.0. stressThresholds() would then derive an RMSSD
    // threshold of 0, and "rmssd < 0" is never true, so stress could never be
    // detected for that profile at all. Floor it at a physiologically sane
    // value instead.
    defaultRMSSD = max(defaultRMSSD, _minimumBaselineRMSSD);

    baselineHeartRate = defaultHeartRate;
    baselineRMSSD = defaultRMSSD;

    return (defaultHeartRate, defaultRMSSD);
  }

  /// Lowest baseline RMSSD the profile defaults may produce. Roughly the
  /// bottom of the adult resting range; below this the stress thresholds stop
  /// being meaningful.
  static const double _minimumBaselineRMSSD = 12.0;

  /// Thresholds derived from the baseline biometrics and a sensitivity
  /// fraction. Pass [stressThreshold] to override the account's saved
  /// sensitivity for a single call (e.g. a demo session) without persisting
  /// it; omit it to use (and, the first time, cache) the account's own.
  (int, double) stressThresholds({double? stressThreshold}) {
    final (baselineHeartRate, baselineRMSSD) = baselineBiometrics;

    // if a treshold is provided, use it; otherwise, use the user's stored threshold or default to 10%
    final threshold = stressThreshold ?? this.stressThreshold ?? 0.1;

    // If the user's stored threshold is null, set it to 10% for future reference
    this.stressThreshold ??= 0.1;

    final heartRateThreshold = (baselineHeartRate * (1 + threshold)).round();
    final rmssdThreshold = baselineRMSSD * (1 - threshold);
    return (heartRateThreshold, rmssdThreshold);
  }

  String getContextSummary() {
    return '''User Profile:
- Name: ${firstName != null ? '$firstName' : 'the person you are guiding'}
- Age: $age years old
- Gender: $gender
- Fitness Level: $fitnessLevel
- Meditation Type: $meditationType
- Meditation Environment: $meditationEnvironment
- Additional Preferences: ${additionalPreferences ?? 'None'}
- Resting Heart Rate: ${baselineBiometrics.$1.toStringAsFixed(0)} BPM
- Baseline HRV (RMSSD): ${baselineBiometrics.$2.toStringAsFixed(0)} ms''';
  }
}
