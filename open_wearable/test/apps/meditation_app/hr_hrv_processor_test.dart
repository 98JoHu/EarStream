import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_wearable/apps/meditation_app/model/hr_hrv_processor.dart';
import 'package:open_wearable/apps/meditation_app/model/activity_tracker.dart';
import 'package:open_wearable/apps/meditation_app/model/bio_adaptive_session_config.dart';
import 'package:open_wearable/apps/meditation_app/model/biometric_source.dart';
import 'package:open_wearable/apps/meditation_app/model/measurement_phase.dart';
import 'package:open_wearable/apps/meditation_app/model/meditation_prompt_policy.dart';
import 'package:open_wearable/apps/meditation_app/model/meditation_session_generator.dart';
import 'package:open_wearable/apps/meditation_app/model/stress_detector.dart';
import 'package:open_wearable/apps/meditation_app/model/tencent_tts_client.dart';
import 'package:open_wearable/apps/meditation_app/model/user_account.dart';
import 'package:open_wearable/apps/meditation_app/views/meditation_modes/bio_adaptive_view.dart';

void main() {
  group('HrHrvProcessor.hrvMinimumWindow', () {
    // The setter converts a Duration into sensor ticks via timestampExponent,
    // so it must round-trip for every exponent the sensors actually report.
    // Getting this wrong silently changes how long RMSSD stays null.
    for (final exponent in const [-3, -6]) {
      test('round-trips through tick conversion at exponent $exponent', () {
        final processor = HrHrvProcessor(
          sampleFreq: 200,
          accelerometerFreq: 100,
          timestampExponent: exponent,
        );
        addTearDown(processor.dispose);

        expect(processor.hrvMinimumWindow, const Duration(seconds: 60));

        processor.hrvMinimumWindow = const Duration(seconds: 15);
        expect(processor.hrvMinimumWindow, const Duration(seconds: 15));
      });
    }
  });

  group('meditation environment configuration', () {
    test('loads Tencent selection, key pair, and China region', () {
      final account = UserAccount.fromEnvironment({
        'DEEPSEEK_API_KEY': 'deepseek-demo',
        'TTS_PROVIDER': 'tencent',
        'TENCENT_SECRET_ID': 'AKIDexample',
        'TENCENT_SECRET_KEY': 'secret-example',
        'TENCENT_TTS_REGION': 'ap-guangzhou',
      });

      expect(account.ttsProvider, TtsProviderOption.tencent);
      expect(account.tencentTtsRegion, TencentTtsRegion.chinaGuangzhou);
      expect(account.hasValidTencentKey, isTrue);
      expect(account.hasValidSelectedTtsProvider, isTrue);
      expect(account.hasValidDeepseekKey, isTrue);
    });

    test('accepts the legacy Tencent API key name as SecretKey', () {
      final account = UserAccount.fromEnvironment({
        'TTS_PROVIDER': 'tencent',
        'TENCENT_SECRET_ID': 'AKIDexample',
        'TENCENT_TTS_API_KEY': 'legacy-secret-key',
      });

      expect(account.tencentSecretKey, 'legacy-secret-key');
      expect(account.tencentTtsRegion, TencentTtsRegion.euFrankfurt);
      expect(account.hasValidTencentKey, isTrue);
    });
  });

  group('conference demo configuration', () {
    test('applies the paper parameters without changing standard defaults', () {
      const demo = BioAdaptiveSessionConfig.conferenceDemo;
      const standard = BioAdaptiveSessionConfig.standard;

      expect(demo.includeCalibration, isFalse);
      expect(demo.baselineDuration, const Duration(seconds: 30));
      expect(
        demo.baselineComputationMode,
        BaselineComputationMode.physiologicalOnly,
      );
      expect(demo.stressThresholdOverride, 0.03);
      expect(demo.hrvMinimumWindow, const Duration(seconds: 15));
      expect(demo.meditationSegmentDuration, const Duration(seconds: 30));
      expect(demo.promptPolicy, MeditationPromptPolicy.conferenceDemo);
      expect(demo.allowStressSimulation, isFalse);

      expect(standard.includeCalibration, isTrue);
      expect(standard.calibrationDuration, const Duration(seconds: 30));
      expect(standard.baselineDuration, const Duration(minutes: 5));
      expect(
        standard.baselineComputationMode,
        BaselineComputationMode.profileBlended,
      );
      expect(standard.stressThresholdOverride, isNull);
      expect(standard.hrvMinimumWindow, isNull);
      expect(standard.meditationSegmentDuration, isNull);
      expect(standard.promptPolicy, MeditationPromptPolicy.standard);
      expect(standard.allowStressSimulation, isTrue);
    });

    testWidgets('does not render a stress simulation control', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BioAdaptiveControls(
              earstreamState: EarstreamState.running,
              onStart: () {},
              onResume: () {},
              onPause: () {},
              onSimulateStress: () {},
              onReset: () {},
              showStressSimulation: false,
            ),
          ),
        ),
      );

      expect(find.text('Simulate Stress'), findsNothing);
      expect(find.text('Reset'), findsOneWidget);
    });
  });

  group('demo profile isolation', () {
    test('copies service configuration but no permanent profile data', () {
      final permanent = UserAccount(
        username: 'permanent-user',
        firstName: 'ProfileSecretName',
        lastName: 'ProfileSecretSurname',
        gender: Gender.female,
        age: 93,
        fitnessLevel: FitnessLevel.athlete,
        voiceGender: Gender.male,
        speakingSpeed: SpeakingSpeed.fast,
        meditationType: MeditationType.bodyScan,
        meditationEnvironment: MeditationEnvironment.garden,
        additionalPreferences: 'ProfileSecretPreference',
        stressThreshold: 0.27,
        baselineHeartRate: 111,
        baselineRMSSD: 7,
        deepseekApiKey: 'deepseek-service-key',
        elevenLabsApiKey: 'eleven-service-key',
        ttsProvider: TtsProviderOption.tencent,
        tencentSecretId: 'tencent-service-id',
        tencentSecretKey: 'tencent-service-key',
        tencentTtsRegion: TencentTtsRegion.chinaGuangzhou,
      );
      permanent.hasValidDeepseekKey = true;
      permanent.hasValidElevenLabsKey = true;
      permanent.hasValidTencentKey = true;
      permanent.elevenLabsVoiceId = 'service-voice';

      final demo = UserAccount.forConferenceDemo(
        serviceConfiguration: permanent,
      );

      expect(demo.deepseekApiKey, 'deepseek-service-key');
      expect(demo.tencentSecretId, 'tencent-service-id');
      expect(demo.ttsProvider, TtsProviderOption.tencent);
      expect(demo.hasValidDeepseekKey, isTrue);
      expect(demo.hasValidTencentKey, isTrue);
      expect(demo.username, isNull);
      expect(demo.firstName, isNull);
      expect(demo.lastName, isNull);
      expect(demo.gender, isNull);
      expect(demo.age, isNull);
      expect(demo.fitnessLevel, isNull);
      expect(demo.voiceGender, isNull);
      expect(demo.speakingSpeed, isNull);
      expect(demo.meditationType, isNull);
      expect(demo.meditationEnvironment, isNull);
      expect(demo.additionalPreferences, isNull);
      expect(demo.stressThreshold, isNull);
      expect(demo.baselineHeartRate, isNull);
      expect(demo.baselineRMSSD, isNull);

      demo.meditationType = MeditationType.breathing;
      demo.baselineHeartRate = 70;
      expect(permanent.meditationType, MeditationType.bodyScan);
      expect(permanent.baselineHeartRate, 111);
    });
  });

  group('physiological-only baseline', () {
    test('uses only the mean of locally observed samples', () async {
      final account = UserAccount(
        firstName: 'ProfileSecretName',
        age: 93,
        baselineHeartRate: 111,
        baselineRMSSD: 7,
      );
      final source = _TestBiometricSource();
      final detector = StressDetector(
        thresholds: () => (90, 30),
        baselineHeartRate: () => 70,
      );
      final phase = BaselinePhase(
        userAccount: account,
        duration: const Duration(seconds: 30),
        computationMode: BaselineComputationMode.physiologicalOnly,
      );
      final subscription = phase.activate(
        PhaseContext(source: source, detector: detector),
        () => const Duration(seconds: 10),
      );

      source.add(const HeartRateSample(heartRate: 60, rmssd: 20));
      source.add(const HeartRateSample(heartRate: 80, rmssd: null));
      source.add(const HeartRateSample(heartRate: 100, rmssd: 40));
      await Future<void>.delayed(Duration.zero);

      expect(account.baselineHeartRate, 80);
      expect(account.baselineRMSSD, 30);
      expect(phase.canAdvance, isTrue);

      await subscription.cancel();
      detector.dispose();
      source.dispose();
    });
  });

  group('conference prompt privacy', () {
    test('sends only attendee session preferences to DeepSeek', () async {
      final requestBodies = <String>[];
      var call = 0;
      final client = MockClient((request) async {
        requestBodies.add(request.body);
        call++;
        final content = call == 1
            ? jsonEncode({
                'welcomeMessage': 'Welcome.',
                'completionMessage': 'Well done.',
                'segment': {
                  'segmentId': 1,
                  'instruction': 'Breathe slowly.',
                  'durationSeconds': 30,
                },
              })
            : jsonEncode({
                'segmentId': 2,
                'instruction': 'Continue breathing.',
                'durationSeconds': 30,
              });
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
              },
            ],
          }),
          200,
        );
      });
      final account = UserAccount(
        firstName: 'ProfileSecretName',
        lastName: 'ProfileSecretSurname',
        age: 93,
        gender: Gender.female,
        fitnessLevel: FitnessLevel.athlete,
        additionalPreferences: 'ProfileSecretPreference',
        baselineHeartRate: 111,
        baselineRMSSD: 7,
        meditationType: MeditationType.bodyScan,
        meditationEnvironment: MeditationEnvironment.garden,
        deepseekApiKey: 'service-key',
      );
      final script = AdaptiveMeditationScript(
        account: account,
        maxSegments: 2,
        segmentDuration: const Duration(seconds: 30),
        promptPolicy: MeditationPromptPolicy.conferenceDemo,
        client: client,
      );
      addTearDown(script.dispose);

      await script.begin();
      await script.nextSegment(
        const HeartRateSample(heartRate: 197, rmssd: 3.14159),
      );

      final cloudPayload = requestBodies.join('\n');
      expect(cloudPayload, contains('Body Scan'));
      expect(cloudPayload, contains('Garden'));
      expect(cloudPayload, isNot(contains('ProfileSecretName')));
      expect(cloudPayload, isNot(contains('ProfileSecretSurname')));
      expect(cloudPayload, isNot(contains('ProfileSecretPreference')));
      expect(cloudPayload, isNot(contains('93 years')));
      expect(cloudPayload, isNot(contains('111 BPM')));
      expect(cloudPayload, isNot(contains('197 bpm')));
      expect(cloudPayload, isNot(contains('3 ms')));
    });
  });

  group('TencentTtsClient', () {
    test('signs a Frankfurt request and decodes returned audio', () async {
      late http.Request capturedRequest;
      final client = TencentTtsClient(
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'Response': {
                'Audio': base64Encode(const [1, 2, 3, 4]),
                'RequestId': 'request-id',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);

      final audio = await client.synthesize(
        text: 'Breathe in slowly.',
        secretId: 'AKIDexample',
        secretKey: 'secret-example',
        region: TencentTtsRegion.euFrankfurt,
        voiceType: 1051,
        speed: -1,
        requestTime: DateTime.utc(2026, 9, 18, 12),
      );

      expect(audio, orderedEquals(const [1, 2, 3, 4]));
      expect(
        capturedRequest.url.host,
        'tts.eu-frankfurt.tencentcloudapi.com',
      );
      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.headers['X-TC-Action'], 'TextToVoice');
      expect(capturedRequest.headers['X-TC-Region'], 'eu-frankfurt');
      final authorization = capturedRequest.headers['Authorization']!;
      expect(authorization, startsWith('TC3-HMAC-SHA256 Credential='));
      expect(authorization, contains('AKIDexample/2026-09-18/tts/tc3_request'));
      expect(authorization, isNot(contains('secret-example')));

      final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(payload['Text'], 'Breathe in slowly.');
      expect(payload['Codec'], 'mp3');
      expect(payload['VoiceType'], 1051);
      expect(payload['Speed'], -1);
    });

    test('splits long Latin and Chinese text within service limits', () {
      final latin = List.filled(700, 'calm').join(' ');
      final latinChunks = splitTencentTtsText(latin);
      expect(latinChunks.length, greaterThan(1));
      expect(latinChunks.every((chunk) => chunk.length <= 460), isTrue);
      expect(latinChunks.join(' '), latin);

      final chinese = List.filled(400, '静').join();
      final chineseChunks = splitTencentTtsText(chinese);
      expect(chineseChunks.length, greaterThan(1));
      expect(chineseChunks.every((chunk) => chunk.runes.length <= 115), isTrue);
      expect(chineseChunks.join(), chinese);
    });
  });
}

class _TestBiometricSource implements BiometricSource {
  final StreamController<HeartRateSample> _controller =
      StreamController.broadcast(sync: true);
  final ValueNotifier<ActivityLevel> _activity =
      ValueNotifier(ActivityLevel.resting);

  void add(HeartRateSample sample) => _controller.add(sample);

  @override
  Stream<HeartRateSample> get biometrics => _controller.stream;

  @override
  ValueListenable<ActivityLevel> get activityLevel => _activity;

  @override
  bool get suppressStressDetection => false;

  @override
  void start() {}

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void reset() {}

  @override
  void dispose() {
    _controller.close();
    _activity.dispose();
  }
}
