import 'overall_config.dart';

/// Parameters shared by the two conference-demo experiences.
abstract final class DemoModeConfig {
  // Demo biosignal-adaptive cycle.
  static const bool includeCalibration = true;
  static const Duration calibrationDuration = Duration(seconds: 30);
  static const Duration baselineDuration = Duration(seconds: 30);
  static const double stressThreshold = 0.03;
  static const Duration metricWindowDuration = Duration(seconds: 30);
  static const Duration hrvMinimumWindow = Duration(seconds: 30);
  static const Duration guaranteedMeditationDelay = Duration(minutes: 2);
  // Welcome and completion messages remain outside this generated count.
  static const int biosignalAdaptiveMeditationSegmentCount = 1;
  static const Duration meditationSegmentDuration = Duration(seconds: 30);
  static const bool useBestEffortEstimates = true;
  static const bool allowStressSimulation = false;

  // Personalized meditation-only demo.
  static const int meditationOnlySegmentCount = 3;
  static const Duration meditationOnlySegmentDuration = Duration(seconds: 30);

  // Privacy policy for both demo submodes.
  static const bool includePermanentProfileInPrompt = false;
  static const bool includePhysiologicalDataInPrompt = false;

  // Mainland China deployment checklist:
  // 1. Use Tencent rather than ElevenLabs for TTS.
  // 2. Select the Mainland China Tencent endpoint/region below.
  // 3. Supply a SecretId/SecretKey belonging to a Tencent Cloud account where
  //    Mainland China TTS is activated. International credentials/service
  //    activation are not assumed to carry over.
  // 4. DeepSeek needs no endpoint change; keep its existing API key and global
  //    base URL. No profile or physiological values are added to its prompts.
  //
  // These values document the exact .env edits. They are not automatically
  // applied, so EU and China builds continue to follow the user's selection.
  static const Map<String, String> chinaEnvironmentOverrides = {
    OverallMeditationConfig.ttsProviderEnvironmentKey:
        OverallMeditationConfig.tencentProviderEnvironmentValue,
    OverallMeditationConfig.tencentRegionEnvironmentKey:
        OverallMeditationConfig.tencentChinaRegion,
  };
  static const String chinaTencentApiHost =
      OverallMeditationConfig.tencentChinaHost;
  static const String chinaTencentSecretIdEnvironmentKey =
      OverallMeditationConfig.tencentSecretIdEnvironmentKey;
  static const String chinaTencentSecretKeyEnvironmentKey =
      OverallMeditationConfig.tencentSecretKeyEnvironmentKey;
  static const String chinaTencentLegacySecretKeyEnvironmentKey =
      OverallMeditationConfig.tencentLegacySecretKeyEnvironmentKey;
  static const bool chinaRequiresDeepseekEndpointOverride = false;
  static const String chinaDeepseekApiBaseUrl =
      OverallMeditationConfig.deepseekApiBaseUrl;

  // Current EU/international Tencent counterpart for comparison.
  static const Map<String, String> internationalEnvironmentOverrides = {
    OverallMeditationConfig.ttsProviderEnvironmentKey:
        OverallMeditationConfig.tencentProviderEnvironmentValue,
    OverallMeditationConfig.tencentRegionEnvironmentKey:
        OverallMeditationConfig.tencentInternationalRegion,
  };
  static const String internationalTencentApiHost =
      OverallMeditationConfig.tencentInternationalHost;
}
