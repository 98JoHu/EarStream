import 'dart:convert';
import 'dart:async';
import 'dart:math';

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
import 'package:open_wearable/apps/meditation_app/model/meditation_analytics.dart';
import 'package:open_wearable/apps/meditation_app/model/meditation.dart';
import 'package:open_wearable/apps/meditation_app/model/meditation_session_generator.dart';
import 'package:open_wearable/apps/meditation_app/model/monitoring_meditation_deadline.dart';
import 'package:open_wearable/apps/meditation_app/model/stress_detector.dart';
import 'package:open_wearable/apps/meditation_app/model/tencent_tts_client.dart';
import 'package:open_wearable/apps/meditation_app/model/user_account.dart';
import 'package:open_wearable/apps/meditation_app/views/meditation_modes/bio_adaptive_view.dart';
import 'package:open_wearable/apps/meditation_app/views/pages/weekly_analytics_page.dart';
import 'package:open_wearable/apps/meditation_app/widgets/meditation_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('applies only the demo-specific shortened window', () {
      const demo = BioAdaptiveSessionConfig.conferenceDemo;
      const standard = BioAdaptiveSessionConfig.standard;
      final demoProcessor = HrHrvProcessor(
        sampleFreq: 200,
        accelerometerFreq: 100,
        timestampExponent: -3,
        hrvMinimumWindow: demo.hrvMinimumWindow,
        metricWindowDuration: demo.metricWindowDuration,
      );
      final standardProcessor = HrHrvProcessor(
        sampleFreq: 200,
        accelerometerFreq: 100,
        timestampExponent: -3,
        hrvMinimumWindow: standard.hrvMinimumWindow,
      );
      addTearDown(demoProcessor.dispose);
      addTearDown(standardProcessor.dispose);

      expect(
        demoProcessor.hrvMinimumWindow,
        const Duration(seconds: 30),
      );
      expect(demoProcessor.heartRateWindow, const Duration(seconds: 30));
      expect(
        demoProcessor.metricEligibilityWindow,
        const Duration(seconds: 30),
      );
      expect(demoProcessor.hrvHistoryWindow, const Duration(seconds: 30));
      expect(
        standardProcessor.hrvMinimumWindow,
        const Duration(seconds: 60),
      );
      expect(standardProcessor.heartRateWindow, const Duration(seconds: 10));
      expect(
        standardProcessor.metricEligibilityWindow,
        const Duration(seconds: 4),
      );
      expect(standardProcessor.hrvHistoryWindow, const Duration(minutes: 5));
    });
  });

  test('calibration warms the pipeline without publishing biometrics',
      () async {
    final processor = HrHrvProcessor(
      sampleFreq: 200,
      accelerometerFreq: 100,
      timestampExponent: -3,
    );
    addTearDown(processor.dispose);
    final samples = <HeartRateSample>[];
    final subscription = processor.biometricStream.listen(samples.add);
    addTearDown(subscription.cancel);

    processor.beginCalibration();
    processor.emitSimulatedSample(92, 28);
    await Future<void>.delayed(Duration.zero);
    expect(samples, isEmpty);
    expect(processor.latestSample, isNull);

    processor.beginMeasurement();
    processor.emitSimulatedSample(72, 44);
    await Future<void>.delayed(Duration.zero);
    expect(samples, hasLength(1));
    expect(samples.single.heartRate, 72);
    expect(samples.single.rmssd, 44);
  });

  test('demo metrics become eligible only at the 30-second deadline', () async {
    final epoch = DateTime(2026);
    var now = epoch;
    final processor = HrHrvProcessor(
      sampleFreq: 200,
      accelerometerFreq: 100,
      timestampExponent: -3,
      hrvMinimumWindow:
          BioAdaptiveSessionConfig.conferenceDemo.hrvMinimumWindow,
      metricWindowDuration:
          BioAdaptiveSessionConfig.conferenceDemo.metricWindowDuration,
      publishBestEffortEstimates:
          BioAdaptiveSessionConfig.conferenceDemo.useBestEffortEstimates,
      now: () => now,
    );
    addTearDown(processor.dispose);
    final samples = <HeartRateSample>[];
    final subscription = processor.biometricStream.listen(samples.add);
    addTearDown(subscription.cancel);

    var phase = 0.0;
    void feedWindow({required int startMs, required int durationSeconds}) {
      const sampleRate = 200;
      const stepMs = 1000 ~/ sampleRate;
      for (var index = 0; index < durationSeconds * sampleRate; index++) {
        final timestamp = startMs + (index * stepMs);
        final timeSeconds = timestamp / 1000.0;
        final pulseHz = 1.15 + (0.08 * sin(2 * pi * 0.1 * timeSeconds));
        phase += 2 * pi * pulseHz / sampleRate;
        final optical = 1000 + (120 * sin(phase));
        now = epoch.add(Duration(milliseconds: timestamp));
        processor.processPpgSample(
          timestamp,
          optical * 0.9,
          optical * 0.8,
          optical,
          0,
        );
      }
    }

    processor.beginCalibration();
    feedWindow(startMs: 0, durationSeconds: 30);
    expect(samples, isEmpty);
    expect(processor.bestEffortEstimate, isNull);

    processor.beginMeasurement();
    feedWindow(startMs: 30000, durationSeconds: 29);
    await Future<void>.delayed(Duration.zero);
    expect(samples, isEmpty);
    expect(processor.bestEffortEstimate, isNull);

    feedWindow(startMs: 59000, durationSeconds: 1);
    final deadlineEstimate = processor.finalizeBaselineEstimate();

    expect(deadlineEstimate, isNotNull);
    expect(deadlineEstimate!.rmssd, isNotNull);
    expect(processor.bestEffortEstimate, deadlineEstimate);
  });

  test('demo deadline can use retained stable calibration signal', () {
    final epoch = DateTime(2026);
    var now = epoch;
    final processor = HrHrvProcessor(
      sampleFreq: 200,
      accelerometerFreq: 100,
      timestampExponent: -3,
      hrvMinimumWindow:
          BioAdaptiveSessionConfig.conferenceDemo.hrvMinimumWindow,
      metricWindowDuration:
          BioAdaptiveSessionConfig.conferenceDemo.metricWindowDuration,
      publishBestEffortEstimates: true,
      now: () => now,
    );
    addTearDown(processor.dispose);

    var phase = 0.0;
    processor.beginCalibration();
    for (var index = 0; index < 30 * 200; index++) {
      final timestamp = index * 5;
      final pulseHz = 1.1 + (0.06 * sin(2 * pi * 0.08 * index / 200));
      phase += 2 * pi * pulseHz / 200;
      final optical = 1000 + (110 * sin(phase));
      now = epoch.add(Duration(milliseconds: timestamp));
      processor.processPpgSample(
        timestamp,
        optical * 0.9,
        optical * 0.8,
        optical,
        0,
      );
    }

    // The calibration stays invisible to the live estimator.
    expect(processor.bestEffortEstimate, isNull);

    processor.beginMeasurement();
    // Deliberately provide an unusable flat baseline window. The deadline
    // estimator must still recover from the stable tail of calibration.
    for (var index = 0; index < 30 * 200; index++) {
      final timestamp = 30000 + (index * 5);
      now = epoch.add(Duration(milliseconds: timestamp));
      processor.processPpgSample(timestamp, 1000, 900, 800, 0);
    }

    final estimate = processor.finalizeBaselineEstimate();
    expect(estimate, isNotNull);
    expect(estimate!.heartRate, inInclusiveRange(30, 240));
    expect(estimate.rmssd, isNotNull);
    expect(estimate.rmssd, inInclusiveRange(0, 300));
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

      expect(demo.includeCalibration, isTrue);
      expect(demo.calibrationDuration, const Duration(seconds: 30));
      expect(demo.baselineDuration, const Duration(seconds: 30));
      expect(
        demo.baselineComputationMode,
        BaselineComputationMode.physiologicalOnly,
      );
      expect(demo.stressThresholdOverride, 0.03);
      expect(demo.hrvMinimumWindow, const Duration(seconds: 30));
      expect(demo.metricWindowDuration, const Duration(seconds: 30));
      expect(demo.guaranteedMeditationDelay, const Duration(minutes: 2));
      expect(demo.useBestEffortEstimates, isTrue);
      expect(demo.meditationSegmentDuration, const Duration(seconds: 30));
      expect(demo.promptPolicy, MeditationPromptPolicy.conferenceDemo);
      expect(demo.allowStressSimulation, isFalse);

      expect(standard.includeCalibration, isTrue);
      expect(standard.calibrationDuration, const Duration(seconds: 30));
      expect(standard.baselineDuration, const Duration(minutes: 5));
      expect(
        standard.baselineComputationMode,
        BaselineComputationMode.physiologicalOnly,
      );
      expect(standard.stressThresholdOverride, isNull);
      expect(standard.hrvMinimumWindow, isNull);
      expect(standard.metricWindowDuration, isNull);
      expect(standard.guaranteedMeditationDelay, isNull);
      expect(standard.useBestEffortEstimates, isFalse);
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

  group('conference monitoring deadline', () {
    testWidgets('fires once after two minutes of monitoring', (tester) async {
      var triggerCount = 0;
      final deadline = MonitoringMeditationDeadline(
        delay: const Duration(minutes: 2),
        onElapsed: () => triggerCount++,
      );
      addTearDown(deadline.dispose);

      deadline.enterMonitoring();
      await tester.pump(const Duration(seconds: 119));
      expect(triggerCount, 0);

      await tester.pump(const Duration(seconds: 1));
      expect(triggerCount, 1);

      await tester.pump(const Duration(minutes: 2));
      expect(triggerCount, 1);
    });

    testWidgets('an earlier meditation cancels the guaranteed trigger',
        (tester) async {
      var triggerCount = 0;
      final deadline = MonitoringMeditationDeadline(
        delay: const Duration(minutes: 2),
        onElapsed: () => triggerCount++,
      );
      addTearDown(deadline.dispose);

      deadline.enterMonitoring();
      await tester.pump(const Duration(minutes: 1));
      deadline.satisfy();
      await tester.pump(const Duration(minutes: 2));

      expect(triggerCount, 0);
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
    test('calibration activates filtering without subscribing to metrics', () {
      final source = _TestBiometricSource();
      final detector = StressDetector(
        thresholds: () => (90, 30),
        baselineHeartRate: () => 70,
      );
      final phase = CalibrationPhase();

      final subscription = phase.activate(
        PhaseContext(source: source, detector: detector),
        () => Duration.zero,
      );

      expect(subscription, isNull);
      expect(source.calibrationStarts, 1);
      expect(source.measurementStarts, 0);

      detector.dispose();
      source.dispose();
    });

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
      expect(source.measurementStarts, 1);

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

    test('physiological baseline never advances with missing values', () async {
      final account = UserAccount();
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
      final context = PhaseContext(source: source, detector: detector);
      final subscription = phase.activate(context, () => Duration.zero);

      source.add(const HeartRateSample(heartRate: 64, rmssd: null));
      await Future<void>.delayed(Duration.zero);
      expect(phase.hasValidHeartRate, isTrue);
      expect(phase.hasValidRmssd, isFalse);
      expect(phase.canAdvance, isFalse);
      expect(account.baselineHeartRate, 64);
      expect(account.baselineRMSSD, isNull);

      source.add(const HeartRateSample(heartRate: 66, rmssd: 36));
      await Future<void>.delayed(Duration.zero);
      expect(phase.hasValidRmssd, isTrue);
      expect(phase.canAdvance, isTrue);
      expect(account.baselineRMSSD, 36);

      await subscription.cancel();
      detector.dispose();
      source.dispose();
    });

    test('demo deadline uses only a measured best-effort estimate', () {
      final account = UserAccount();
      final source = _TestBiometricSource();
      final detector = StressDetector(
        thresholds: () => (90, 30),
        baselineHeartRate: () => 70,
      );
      final phase = BaselinePhase(
        userAccount: account,
        duration: const Duration(seconds: 30),
        computationMode: BaselineComputationMode.physiologicalOnly,
        useBestEffortAtDeadline: true,
      );
      final context = PhaseContext(source: source, detector: detector);
      phase.activate(context, () => Duration.zero);

      expect(phase.canAdvance, isFalse);
      phase.complete(context);
      expect(account.baselineHeartRate, isNull);
      expect(account.baselineRMSSD, isNull);

      source.bestEstimate = const HeartRateSample(heartRate: 68, rmssd: 31);
      expect(phase.canAdvance, isTrue);
      phase.complete(context);
      expect(account.baselineHeartRate, 68);
      expect(account.baselineRMSSD, 31);

      detector.dispose();
      source.dispose();
    });

    test('standard baseline retains production timing without profile fallback',
        () async {
      final account = UserAccount();
      final source = _TestBiometricSource();
      final detector = StressDetector(
        thresholds: () => (90, 30),
        baselineHeartRate: () => 70,
      );
      final phase = BaselinePhase(
        userAccount: account,
        duration: BioAdaptiveSessionConfig.standard.baselineDuration,
        computationMode:
            BioAdaptiveSessionConfig.standard.baselineComputationMode,
      );
      final subscription = phase.activate(
        PhaseContext(source: source, detector: detector),
        () => Duration.zero,
      );

      expect(phase.duration, const Duration(minutes: 5));
      expect(phase.canAdvance, isFalse);
      expect(account.baselineHeartRate, isNull);
      expect(account.baselineRMSSD, isNull);

      source.add(const HeartRateSample(heartRate: 65, rmssd: 34));
      await Future<void>.delayed(Duration.zero);

      expect(phase.canAdvance, isTrue);
      expect(account.baselineHeartRate, 65);
      expect(account.baselineRMSSD, 34);

      await subscription.cancel();
      detector.dispose();
      source.dispose();
    });
  });

  group('meditation session presentation', () {
    testWidgets('active sessions show controls without a segment status box',
        (tester) async {
      final meditation = Meditation(userAccount: UserAccount());
      final notifier = ValueNotifier<Meditation?>(meditation);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeditationTile(meditationNotifier: notifier),
          ),
        ),
      );

      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Meditating...'), findsNothing);
      expect(find.textContaining('Segment'), findsNothing);
    });

    testWidgets('finished sessions show success and mood feedback',
        (tester) async {
      final meditation = Meditation(userAccount: UserAccount());
      meditation.phase.value = MeditationPhase.finished;
      final notifier = ValueNotifier<Meditation?>(meditation);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeditationTile(meditationNotifier: notifier),
          ),
        ),
      );

      expect(find.text('Great job!'), findsOneWidget);
      expect(find.text('How do you feel right now?'), findsOneWidget);
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

  group('MeditationAnalyticsStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('combines regular modes and filters records by Monday-based week',
        () async {
      final store = MeditationAnalyticsStore();
      final thisWeek = MeditationAnalyticsStore.startOfWeek(DateTime.now());
      final previousWeek = thisWeek.subtract(const Duration(days: 7));

      await store.recordSession(
        MeditationSessionRecord(
          mode: MeditationAnalyticsMode.bioAdaptive,
          startedAt: thisWeek.add(const Duration(days: 1, hours: 9)),
          endedAt: thisWeek.add(
            const Duration(days: 1, hours: 9, minutes: 4),
          ),
          completed: true,
        ),
      );
      await store.recordSession(
        MeditationSessionRecord(
          mode: MeditationAnalyticsMode.timed,
          startedAt: thisWeek.add(const Duration(days: 3, hours: 18)),
          endedAt: thisWeek.add(
            const Duration(days: 3, hours: 18, minutes: 6),
          ),
          completed: false,
        ),
      );
      await store.recordSession(
        MeditationSessionRecord(
          mode: MeditationAnalyticsMode.timed,
          startedAt: previousWeek.add(const Duration(days: 2, hours: 12)),
          endedAt: previousWeek.add(
            const Duration(days: 2, hours: 12, minutes: 3),
          ),
          completed: true,
        ),
      );

      final current = store.recordsForWeek(thisWeek);
      expect(current, hasLength(2));
      expect(
        current.map((record) => record.mode),
        containsAll([
          MeditationAnalyticsMode.bioAdaptive,
          MeditationAnalyticsMode.timed,
        ]),
      );
      expect(
        current.fold<int>(
          0,
          (seconds, record) => seconds + record.duration.inSeconds,
        ),
        const Duration(minutes: 10).inSeconds,
      );
      expect(store.recordsForWeek(previousWeek), hasLength(1));
    });

    test('persists session records locally and reloads them', () async {
      final startedAt = DateTime.now().subtract(const Duration(minutes: 5));
      final store = MeditationAnalyticsStore();
      await store.recordSession(
        MeditationSessionRecord(
          mode: MeditationAnalyticsMode.bioAdaptive,
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(minutes: 5)),
          completed: true,
        ),
      );

      final reloaded = MeditationAnalyticsStore();
      await reloaded.load();

      expect(reloaded.records, hasLength(1));
      expect(
        reloaded.records.single.mode,
        MeditationAnalyticsMode.bioAdaptive,
      );
      expect(reloaded.records.single.completed, isTrue);
      expect(reloaded.records.single.duration, const Duration(minutes: 5));
    });

    testWidgets('weekly dashboard renders combined mode analytics',
        (tester) async {
      final store = MeditationAnalyticsStore();
      final week = MeditationAnalyticsStore.startOfWeek(DateTime.now());
      await store.recordSession(
        MeditationSessionRecord(
          mode: MeditationAnalyticsMode.bioAdaptive,
          startedAt: week.add(const Duration(hours: 9)),
          endedAt: week.add(const Duration(hours: 9, minutes: 4)),
          completed: true,
        ),
      );
      await store.recordSession(
        MeditationSessionRecord(
          mode: MeditationAnalyticsMode.timed,
          startedAt: week.add(const Duration(days: 1, hours: 18)),
          endedAt: week.add(
            const Duration(days: 1, hours: 18, minutes: 6),
          ),
          completed: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeeklyAnalyticsPage(analyticsStore: store),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Weekly Analytics'), findsOneWidget);
      expect(find.text('Biosignal-Adaptive'), findsWidgets);
      expect(find.text('Timed'), findsWidgets);
      expect(find.text('10 min'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
  int calibrationStarts = 0;
  int measurementStarts = 0;
  HeartRateSample? bestEstimate;

  void add(HeartRateSample sample) {
    if (sample.rmssd != null) bestEstimate = sample;
    _controller.add(sample);
  }

  @override
  Stream<HeartRateSample> get biometrics => _controller.stream;

  @override
  ValueListenable<ActivityLevel> get activityLevel => _activity;

  @override
  bool get suppressStressDetection => false;

  @override
  HeartRateSample? get bestEffortEstimate => bestEstimate;

  @override
  HeartRateSample? finalizeBaselineEstimate() => bestEstimate;

  @override
  void beginCalibration() => calibrationStarts++;

  @override
  void beginMeasurement() => measurementStarts++;

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
