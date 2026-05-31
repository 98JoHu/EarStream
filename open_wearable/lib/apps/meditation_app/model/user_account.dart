enum Gender { male, female, nonBinary, unspecified }

enum FitnessLevel { sedentary, moderate, active, athlete }

class UserAccount {
  String? username;
  String? firstName;
  String? lastName;
  Gender? gender;
  int? age;
  FitnessLevel? fitnessLevel;

  UserAccount({
    this.username,
    this.firstName,
    this.lastName,
    this.gender,
    this.age,
    this.fitnessLevel,
  });
}
