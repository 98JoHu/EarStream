import 'user_account.dart';
import 'activity_detector.dart';

/// Personalized stress detector that adapts to user demographics
class PersonalizedStressDetector {
  final UserAccount userAccount;
  late Map<String, double> thresholds;
  
  PersonalizedStressDetector({required this.userAccount}) {
    thresholds = userAccount.getPersonalizedThresholds();
  }
  
  /// Update thresholds when user account changes
  void updateThresholds() {
    thresholds = userAccount.getPersonalizedThresholds();
  }
  
  /// Get research-based baseline values (resting state) from demographics
  /// Based on scientific literature:
  /// - Nunan et al. (2010): "A Quantitative Systematic Review of Normal Values for Short-Term Heart Rate Variability in Healthy Adults"
  /// - Schroeder et al. (2004): "Hypertension, blood pressure, and heart rate variability"
  /// - Tegegne et al. (2018): "Determinants of heart rate variability in the general population"
  Map<String, double> getResearchBaselines() {
    // Base values for 30-year-old, moderate fitness
    double baselineHr = 72.0;
    double baselineHrv = 42.0; // RMSSD in ms
    
    // Age adjustment (HRV decreases ~1ms RMSSD per year after 25)
    // HR increases ~0.5 BPM per decade
    if (userAccount.age < 25) {
      baselineHr = 68.0;
      baselineHrv = 50.0; // Young adults: 45-60ms RMSSD
    } else if (userAccount.age < 35) {
      baselineHr = 70.0;
      baselineHrv = 42.0; // Adults 25-35: 38-48ms RMSSD
    } else if (userAccount.age < 45) {
      baselineHr = 72.0;
      baselineHrv = 35.0; // Adults 35-45: 30-40ms RMSSD
    } else if (userAccount.age < 55) {
      baselineHr = 74.0;
      baselineHrv = 28.0; // Adults 45-55: 25-35ms RMSSD
    } else if (userAccount.age < 65) {
      baselineHr = 76.0;
      baselineHrv = 22.0; // Adults 55-65: 20-28ms RMSSD
    } else {
      baselineHr = 78.0;
      baselineHrv = 18.0; // Seniors 65+: 15-25ms RMSSD
    }
    
    // Gender adjustment (Tegegne 2018: females ~5-8ms lower RMSSD, 3-5 BPM higher HR)
    if (userAccount.gender == 'male') {
      baselineHr -= 4.0;
      baselineHrv += 6.0; // Males: higher parasympathetic tone
    } else if (userAccount.gender == 'female') {
      baselineHr += 4.0;
      baselineHrv -= 6.0; // Females: typically lower HRV
    }
    
    // Fitness level adjustment (athletes can have 2-3x higher HRV)
    switch (userAccount.fitnessLevel) {
      case 'sedentary':
        baselineHr += 8.0; // Sedentary: higher resting HR
        baselineHrv -= 12.0; // Sedentary: 20-40% lower HRV
        break;
      case 'active':
        baselineHr -= 6.0; // Active: lower resting HR
        baselineHrv += 15.0; // Active: 30-50% higher HRV
        break;
      case 'athlete':
        baselineHr -= 12.0; // Athletes: bradycardia (50-60 BPM)
        baselineHrv += 35.0; // Athletes: 80-120ms RMSSD typical
        break;
      default: // moderate
        // Use base values
        break;
    }
    
    // Use user's measured values if available (override research estimates)
    if (userAccount.restingHr != null) {
      baselineHr = userAccount.restingHr!;
    }
    
    if (userAccount.baselineHrv != null) {
      baselineHrv = userAccount.baselineHrv!;
    }
    
    return {
      'baselineHr': baselineHr,
      'baselineHrv': baselineHrv,
    };
  }
  
  /// Check if user is currently stressed
  /// Returns true if HR is elevated OR HRV is low
  /// Activity-aware: accounts for exercise-induced HR elevation
  bool isStressed(double currentHr, double currentHrv, {ActivityLevel? activityLevel}) {
    if (currentHrv < 0) return false; // No HRV data yet
    
    // If user is exercising (moderate+ activity), don't consider them stressed
    // High HR during exercise is normal and expected
    if (activityLevel != null && activityLevel.index >= ActivityLevel.moderate.index) {
      return false; // Not stressed - just exercising!
    }
    
    final hrStressed = currentHr > thresholds['stressHrThreshold']!;
    final hrvStressed = currentHrv < thresholds['stressHrvThreshold']!;
    
    return hrStressed || hrvStressed;
  }
  
  /// Check if user is relaxed
  /// Returns true if HR is low AND HRV is high
  bool isRelaxed(double currentHr, double currentHrv) {
    if (currentHrv < 0) return false; // No HRV data yet
    
    final hrRelaxed = currentHr < thresholds['relaxHrThreshold']!;
    final hrvRelaxed = currentHrv > thresholds['relaxHrvThreshold']!;
    
    return hrRelaxed && hrvRelaxed;
  }
  
  /// Get stress level as percentage (0-100)
  /// Considers both HR and HRV
  /// Activity-aware: returns 0 if user is exercising
  double getStressLevel(double currentHr, double currentHrv, {ActivityLevel? activityLevel}) {
    if (currentHrv < 0) return 0; // No data yet
    
    // If exercising, stress level is 0 (HR elevation is normal)
    if (activityLevel != null && activityLevel.index >= ActivityLevel.moderate.index) {
      return 0;
    }
    
    // HR contribution (0-50%)
    final hrStress = ((currentHr - thresholds['relaxHrThreshold']!) / 
        (thresholds['stressHrThreshold']! - thresholds['relaxHrThreshold']!))
        .clamp(0.0, 1.0) * 50;
    
    // HRV contribution (0-50%)
    final hrvStress = ((thresholds['relaxHrvThreshold']! - currentHrv) / 
        (thresholds['relaxHrvThreshold']! - thresholds['stressHrvThreshold']!))
        .clamp(0.0, 1.0) * 50;
    
    return (hrStress + hrvStress).clamp(0.0, 100.0);
  }
  
  /// Get stress category as string
  /// Activity-aware: returns 'exercising' during physical activity
  String getStressCategory(double currentHr, double currentHrv, {ActivityLevel? activityLevel}) {
    if (currentHrv < 0) return 'measuring';
    
    // Check if exercising first
    if (activityLevel != null && activityLevel.index >= ActivityLevel.moderate.index) {
      return 'exercising';
    }
    
    if (isRelaxed(currentHr, currentHrv)) {
      return 'relaxed';
    } else if (isStressed(currentHr, currentHrv, activityLevel: activityLevel)) {
      return 'stressed';
    } else {
      return 'normal';
    }
  }
  
  /// Get detailed stress analysis
  /// Activity-aware: includes activity level in analysis
  Map<String, dynamic> getStressAnalysis(double currentHr, double currentHrv, {ActivityLevel? activityLevel}) {
    final stressLevel = getStressLevel(currentHr, currentHrv, activityLevel: activityLevel);
    final category = getStressCategory(currentHr, currentHrv, activityLevel: activityLevel);
    
    // Calculate percentage from baseline
    final hrAboveBaseline = ((currentHr - thresholds['relaxHrThreshold']!) / 
        thresholds['relaxHrThreshold']! * 100).clamp(-100.0, 100.0);
    
    final hrvBelowBaseline = ((thresholds['relaxHrvThreshold']! - currentHrv) / 
        thresholds['relaxHrvThreshold']! * 100).clamp(-100.0, 100.0);
    
    return {
      'stressLevel': stressLevel,
      'category': category,
      'isStressed': isStressed(currentHr, currentHrv, activityLevel: activityLevel),
      'isRelaxed': isRelaxed(currentHr, currentHrv),
      'hrAboveBaseline': hrAboveBaseline,
      'hrvBelowBaseline': hrvBelowBaseline,
      'thresholds': thresholds,
      'activityLevel': activityLevel?.name ?? 'unknown',
      'isExercising': activityLevel != null && activityLevel.index >= ActivityLevel.moderate.index,
    };
  }
  
  /// Get recommendations based on stress level
  String getRecommendation(double currentHr, double currentHrv) {
    final analysis = getStressAnalysis(currentHr, currentHrv);
    final stressLevel = analysis['stressLevel'] as double;
    
    if (stressLevel < 20) {
      return 'You\'re doing great! Your stress levels are low.';
    } else if (stressLevel < 40) {
      return 'Mild stress detected. Consider taking a short break.';
    } else if (stressLevel < 60) {
      return 'Moderate stress. A meditation session would be beneficial.';
    } else if (stressLevel < 80) {
      return 'High stress detected. We recommend starting a meditation session now.';
    } else {
      return 'Very high stress levels. Please take immediate action to relax.';
    }
  }
  
  /// Check if stress is improving during meditation
  bool isImprovingDuringMeditation({
    required double startHr,
    required double startHrv,
    required double currentHr,
    required double currentHrv,
  }) {
    // Check for 10% improvement in either metric
    final hrImprovement = (startHr - currentHr) / startHr;
    final hrvImprovement = (currentHrv - startHrv) / startHrv;
    
    return hrImprovement >= 0.10 || hrvImprovement >= 0.10;
  }
  
  /// Check if ready to end meditation session
  /// 
  /// Adaptive relaxation criteria based on physiological feedback:
  /// - Prioritizes HRV as primary stress indicator (more robust to noise)
  /// - Accounts for individual baselines and relative improvement
  /// - Allows early exit if deeply relaxed state is achieved
  bool isReadyToEndSession({
    required double startHr,
    required double startHrv,
    required double currentHr,
    required double currentHrv,
    required int iterationCount,
  }) {
    // Must have done at least 2 iterations for a meaningful session
    if (iterationCount < 2) return false;
    
    final isNowRelaxed = isRelaxed(currentHr, currentHrv);
    final hrImprovement = (startHr - currentHr) / startHr;
    final hrvImprovement = (currentHrv - startHrv) / startHrv;
    final stressLevel = getStressLevel(currentHr, currentHrv);
    
    // SCENARIO 1: Excellent HRV improvement (>30%)
    // If HRV improves this much, person IS relaxed regardless of HR
    // (HR reading might be inaccurate due to poor sensor contact)
    if (hrvImprovement >= 0.30 && stressLevel < 40) {
      return true; // Strong relaxation signal
    }
    
    // SCENARIO 2: Very strong HRV improvement (>25%) + low stress
    if (hrvImprovement >= 0.25 && stressLevel < 30) {
      return true;
    }
    
    // SCENARIO 3: Good HRV improvement (>20%) + person is now relaxed
    if (hrvImprovement >= 0.20 && isNowRelaxed) {
      return true;
    }
    
    // SCENARIO 4: BOTH metrics improved significantly
    // HR improved by 10%+ AND HRV improved by 20%+
    if (hrImprovement >= 0.10 && hrvImprovement >= 0.20) {
      return true;
    }
    
    // SCENARIO 5: Person is clearly relaxed (even without big improvement)
    // AND stress level is very low
    if (isNowRelaxed && stressLevel < 20 && hrvImprovement >= 0.10) {
      return true;
    }
    
    return false;
  }
  
  /// Get reason why session can end (for logging/UI)
  String getEndSessionReason({
    required double startHr,
    required double startHrv,
    required double currentHr,
    required double currentHrv,
  }) {
    final isNowRelaxed = isRelaxed(currentHr, currentHrv);
    final hrImprovement = (startHr - currentHr) / startHr;
    final hrvImprovement = (currentHrv - startHrv) / startHrv;
    final hrImprovementPct = hrImprovement * 100;
    final hrvImprovementPct = hrvImprovement * 100;
    final stressLevel = getStressLevel(currentHr, currentHrv);
    
    // Match the scenarios from isReadyToEndSession
    if (hrvImprovement >= 0.30 && stressLevel < 40) {
      return 'Excellent HRV improvement (${hrvImprovementPct.toStringAsFixed(1)}%) - deeply relaxed';
    } else if (hrvImprovement >= 0.25 && stressLevel < 30) {
      return 'Strong HRV improvement (${hrvImprovementPct.toStringAsFixed(1)}%) and low stress';
    } else if (hrvImprovement >= 0.20 && isNowRelaxed) {
      return 'Good HRV improvement (${hrvImprovementPct.toStringAsFixed(1)}%) - now relaxed';
    } else if (hrImprovement >= 0.10 && hrvImprovement >= 0.20) {
      return 'Both metrics improved (HR: ${hrImprovementPct.toStringAsFixed(1)}%, HRV: ${hrvImprovementPct.toStringAsFixed(1)}%)';
    } else if (isNowRelaxed && stressLevel < 20 && hrvImprovement >= 0.10) {
      return 'Very relaxed state achieved (stress: ${stressLevel.toStringAsFixed(0)}%)';
    } else if (hrImprovement < 0) {
      return 'Heart rate elevated (HR: ${currentHr.toStringAsFixed(0)} BPM) - continue practicing';
    } else if (hrvImprovement < 0.15) {
      return 'HRV improving (${hrvImprovementPct.toStringAsFixed(1)}%) - keep going';
    }
    return 'Making progress - continue with the meditation';
  }
}

