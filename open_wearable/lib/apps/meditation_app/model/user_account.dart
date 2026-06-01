enum Gender { male, female, nonBinary, unspecified }

enum FitnessLevel { sedentary, moderate, active, athlete }

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
  String? meditationEnvironment;
  String? additionalPreferences;
  double? stressThreshold;

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
  });
}
