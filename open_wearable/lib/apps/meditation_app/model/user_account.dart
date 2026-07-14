enum Gender { male, female, nonBinary, unspecified }

enum FitnessLevel { sedentary, moderate, active, athlete }

enum MeditationEnvironment {
  nature(
    label: "Peaceful Nature",
    assetPath: "Peaceful_Nature.wav",
  ),
  ocean(
    label: "Ocean beach",
    assetPath: "Ocean_Beach.wav",
  ),
  mountain(
    label: "Mountain",
    assetPath: "Mountain.wav",
  ),
  forest(
    label: "Forest",
    assetPath: "Forest.wav",
  ),
  garden(
    label: "Garden",
    assetPath: "Garden.mp3",
  );

  final String label;
  final String assetPath;
  const MeditationEnvironment({required this.label, required this.assetPath});
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
  String? voiceGender;
  String? speakingSpeed;
  String? meditationType;
  MeditationEnvironment? meditationEnvironment;
  String? additionalPreferences;
  double? stressThreshold;

  // API keys and tokens
  String? outlookSuppressionToken;
  String? deepseekApiKey;
  String? elevenLabsApiKey;

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
    baselineHeartRate = defaultHeartRate;
    baselineRMSSD = defaultRMSSD;

    return (defaultHeartRate, defaultRMSSD);
  }

  (int, double) get stressThresholds {
    final (baselineHeartRate, baselineRMSSD) = baselineBiometrics;

    final threshold = stressThreshold ?? 0.1;
    stressThreshold ??= threshold;

    final heartRateThreshold = (baselineHeartRate * (1 + threshold)).round();
    final rmssdThreshold = baselineRMSSD * (1 - threshold);
    return (heartRateThreshold, rmssdThreshold);
  }
}
