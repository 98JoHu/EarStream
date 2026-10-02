// Covers the on-device Kokoro voice: selection, voice/speed mapping, the WAV
// the engine hands to the player, and every way the local route can be absent.
//
// The native library and the 340 MB model are not available here, so the
// engine itself is replaced through KokoroTtsEngine.startOverride and the
// platform channel through KokoroModelInstaller.invokeOverride. What is
// exercised for real is everything the app builds on top of them.

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/apps/meditation_app/configs/overall_config.dart';
import 'package:open_wearable/apps/meditation_app/model/kokoro_model_installer.dart';
import 'package:open_wearable/apps/meditation_app/model/kokoro_tts_engine.dart';
import 'package:open_wearable/apps/meditation_app/model/service_connection_manager.dart';
import 'package:open_wearable/apps/meditation_app/model/tts_service.dart';
import 'package:open_wearable/apps/meditation_app/model/user_account.dart';

import 'fake_audio_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // TtsService builds an AudioPlayer for cloud and local audio alike.
  final audio = FakeAudioPlatform();
  setUpAll(audio.install);
  tearDownAll(audio.uninstall);

  setUp(() {
    KokoroTtsEngine.resetForTesting();
    KokoroModelInstaller.resetForTesting();
  });

  tearDown(() {
    KokoroTtsEngine.resetForTesting();
    KokoroModelInstaller.resetForTesting();
  });

  group('local voice selection', () {
    test('the environment can select the on-device voice', () {
      expect(
        TtsProviderOption.fromConfig(
          OverallMeditationConfig.kokoroProviderEnvironmentValue,
        ),
        TtsProviderOption.kokoro,
      );
      expect(TtsProviderOption.fromConfig('KOKORO'), TtsProviderOption.kokoro);
      expect(TtsProviderOption.fromConfig('local'), TtsProviderOption.kokoro);
    });

    test('an unknown provider still falls back to ElevenLabs', () {
      // Adding a third option must not change what an old or empty .env does.
      expect(TtsProviderOption.fromConfig(null), TtsProviderOption.elevenLabs);
      expect(TtsProviderOption.fromConfig(''), TtsProviderOption.elevenLabs);
      expect(
        TtsProviderOption.fromConfig('something-else'),
        TtsProviderOption.elevenLabs,
      );
      expect(
        TtsProviderOption.fromConfig('tencent'),
        TtsProviderOption.tencent,
      );
    });

    test('only the Kokoro option is marked as running locally', () {
      expect(TtsProviderOption.kokoro.isLocal, isTrue);
      expect(TtsProviderOption.elevenLabs.isLocal, isFalse);
      expect(TtsProviderOption.tencent.isLocal, isFalse);
    });

    test('a demo account inherits the bundled model', () {
      // The model belongs to the build, not the attendee, so a demo session
      // must not report the local voice as missing the way it would for
      // profile data that is deliberately not copied.
      final configured = UserAccount(ttsProvider: TtsProviderOption.kokoro)
        ..hasValidKokoroModel = true;

      final demo = UserAccount.forConferenceDemo(
        serviceConfiguration: configured,
      );

      expect(demo.ttsProvider, TtsProviderOption.kokoro);
      expect(demo.hasValidKokoroModel, isTrue);
      expect(demo.hasValidSelectedTtsProvider, isTrue);
    });

    test('the local voice is usable without any API key', () {
      final account = UserAccount(ttsProvider: TtsProviderOption.kokoro);
      expect(account.hasValidSelectedTtsProvider, isFalse);

      account.hasValidKokoroModel = true;
      expect(account.hasValidSelectedTtsProvider, isTrue);
      expect(account.hasValidElevenLabsKey, isFalse);
      expect(account.hasValidTencentKey, isFalse);
    });
  });

  group('voice and speed mapping', () {
    test('the two configured voices are the ones the model ships', () {
      // Positions in kokoro-multi-lang-v1_0's own voice list, taken from the
      // sherpa-onnx generator that builds voices.bin. They differ from the
      // 8 and 10 the same two voices had in kokoro-multi-lang-v1_0, so a model swap
      // that forgets them would silently pick a different speaker.
      expect(OverallMeditationConfig.kokoroFemaleVoiceName, 'bf_isabella');
      expect(OverallMeditationConfig.kokoroFemaleSpeakerId, 22);
      expect(OverallMeditationConfig.kokoroMaleVoiceName, 'bm_lewis');
      expect(OverallMeditationConfig.kokoroMaleSpeakerId, 27);
    });

    test('the default voice setting picks the speaker', () async {
      final female = await _synthesizeWith(voiceGender: Gender.female);
      expect(female.speakerId, OverallMeditationConfig.kokoroFemaleSpeakerId);

      final male = await _synthesizeWith(voiceGender: Gender.male);
      expect(male.speakerId, OverallMeditationConfig.kokoroMaleSpeakerId);
    });

    test('an unspecified voice gender speaks with the female voice', () async {
      final unspecified =
          await _synthesizeWith(voiceGender: Gender.unspecified);
      expect(
        unspecified.speakerId,
        OverallMeditationConfig.kokoroFemaleSpeakerId,
      );
      expect(
        KokoroTtsProvider.voiceNameFor(UserAccount()),
        OverallMeditationConfig.kokoroFemaleVoiceName,
      );
    });

    test('speaking speed maps onto Kokoro\'s own multiplier', () async {
      // Kokoro's multiplier, not the normalized 0-1 scale flutter_tts uses.
      final speeds = <SpeakingSpeed, double>{};
      for (final setting in SpeakingSpeed.values) {
        speeds[setting] = (await _synthesizeWith(speakingSpeed: setting)).speed;
      }

      expect(
        speeds[SpeakingSpeed.verySlow],
        OverallMeditationConfig.kokoroVerySlowSpeechRate,
      );
      expect(
        speeds[SpeakingSpeed.fast],
        OverallMeditationConfig.kokoroFastSpeechRate,
      );

      // The four settings stay ordered and stay in the range Kokoro is
      // sensibly driven at. Pacing a meditation is the silence scale's job;
      // stretching the duration predictor far below 1.0 smears vowels.
      final ordered = SpeakingSpeed.values.map((s) => speeds[s]!).toList();
      for (var i = 1; i < ordered.length; i++) {
        expect(ordered[i], greaterThan(ordered[i - 1]));
      }
      expect(ordered.first, greaterThanOrEqualTo(0.7));
      expect(ordered.last, lessThanOrEqualTo(1.2));
      // Medium is the voice's natural pace, as on the other providers.
      expect(speeds[SpeakingSpeed.medium], 1.0);

      // No explicit choice keeps the recommended slow pace.
      final unset = await _synthesizeWith();
      expect(unset.speed, OverallMeditationConfig.kokoroSlowSpeechRate);
    });
  });

  group('engine configuration', () {
    test('points at the files the model directory actually contains', () {
      final config = configFor('/data/user/0/app/files/kokoro-multi-lang-v1_0');

      expect(config.model.kokoro.model, endsWith('/model.onnx'));
      expect(config.model.kokoro.voices, endsWith('/voices.bin'));
      expect(config.model.kokoro.tokens, endsWith('/tokens.txt'));
      expect(config.model.kokoro.dataDir, endsWith('/espeak-ng-data'));
      // The British list, matching the two British voices.
      expect(config.model.kokoro.lexicon, endsWith('/lexicon-gb-en.txt'));
      expect(
        config.model.kokoro.model,
        startsWith('/data/user/0/app/files/kokoro-multi-lang-v1_0'),
      );
      // Only the Kokoro family is configured.
      expect(config.model.vits.model, isEmpty);
      expect(config.model.matcha.acousticModel, isEmpty);
    });

    test('does not leave sherpa-onnx compressing the pauses', () {
      // sherpa-onnx defaults silenceScale to 0.2, which squeezes every pause
      // longer than 0.2 s down to a fifth. For guided meditation the pauses
      // are the point, so this must be set explicitly and above 1.0.
      final config = configFor('/tmp/kokoro');
      expect(config.silenceScale, OverallMeditationConfig.kokoroSilenceScale);
      expect(config.silenceScale, greaterThan(1.0));
      expect(config.silenceScale, lessThanOrEqualTo(10.0));
    });
  });

  group('local synthesis', () {
    test('produces playable audio rather than device speech', () async {
      final engine = _FakeKokoroEngine();
      KokoroTtsEngine.startOverride = () async => engine;

      final service = TtsService(
        userAccount: UserAccount(
          ttsProvider: TtsProviderOption.kokoro,
        )..hasValidKokoroModel = true,
      );
      addTearDown(service.dispose);

      final narration = await service.prepare('rest your shoulders');
      expect(narration.isDeviceSpoken, isFalse);
      expect(narration.sources, hasLength(1));
      expect((narration.sources!.single as BytesSource).mimeType, 'audio/wav');
      expect(engine.requests.single.text, 'rest your shoulders');
    });

    test('one engine is shared across sessions', () async {
      var starts = 0;
      final engine = _FakeKokoroEngine();
      KokoroTtsEngine.startOverride = () async {
        starts++;
        return engine;
      };

      // Loading the model costs seconds and hundreds of MB, so two sessions in
      // a row must not each pay for it.
      await KokoroTtsEngine.shared();
      await KokoroTtsEngine.shared();
      expect(starts, 1);

      await KokoroTtsEngine.shutdownShared();
      await KokoroTtsEngine.shared();
      expect(starts, 2);
    });

    test('shutting down during a start still releases the engine', () async {
      var shutdowns = 0;
      KokoroTtsEngine.startOverride = () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _FakeKokoroEngine(onShutdown: () => shutdowns++);
      };

      // Leaving the in-app while the model is still loading must not leave a
      // loaded model behind with nothing referencing it.
      final starting = KokoroTtsEngine.shared();
      await KokoroTtsEngine.shutdownShared();
      await starting;

      expect(shutdowns, 1);
    });

    test('concurrent first uses share a single start', () async {
      var starts = 0;
      KokoroTtsEngine.startOverride = () async {
        starts++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _FakeKokoroEngine();
      };

      await Future.wait([
        KokoroTtsEngine.shared(),
        KokoroTtsEngine.shared(),
        KokoroTtsEngine.shared(),
      ]);
      expect(starts, 1);
    });

    test('a build without the model speaks on the device instead', () async {
      KokoroTtsEngine.startOverride = () async => null;

      // The flag is what the settings page reports; with no model it is false
      // and the session takes the device-voice route, as for a missing key.
      final service = TtsService(
        userAccount: UserAccount(ttsProvider: TtsProviderOption.kokoro),
      );
      addTearDown(service.dispose);

      final narration = await service.prepare('nothing to synthesize');
      expect(narration.isDeviceSpoken, isTrue);
    });

    test('a model that disappears surfaces as a voice failure', () async {
      KokoroTtsEngine.startOverride = () async => null;

      // hasValidKokoroModel was true when the session started, so the cloud
      // route was chosen; losing the model must fail loudly rather than
      // silently swapping the voice mid-session.
      final service = TtsService(
        userAccount: UserAccount(
          ttsProvider: TtsProviderOption.kokoro,
        )..hasValidKokoroModel = true,
      );
      addTearDown(service.dispose);

      await expectLater(
        service.prepare('this cannot be spoken'),
        throwsA(isA<TtsSessionException>()),
      );
    });
  });

  group('model installation', () {
    test('a build without the asset directory reports nothing bundled',
        () async {
      KokoroModelInstaller.invokeOverride = (method) async => const {};
      expect(await KokoroModelInstaller.isBundled(), isFalse);
      expect(await KokoroModelInstaller.ensureInstalled(), isNull);
    });

    test('an installed model reports its directory', () async {
      final calls = <String>[];
      KokoroModelInstaller.invokeOverride = (method) async {
        calls.add(method);
        return switch (method) {
          'status' => const {'bundled': true},
          'install' => const {'directory': '/data/app/kokoro-multi-lang-v1_0'},
          _ => const {},
        };
      };

      expect(await KokoroModelInstaller.isBundled(), isTrue);
      expect(
        await KokoroModelInstaller.ensureInstalled(),
        '/data/app/kokoro-multi-lang-v1_0',
      );
      expect(calls, ['status', 'install']);
    });

    test('an empty directory is treated as no model', () async {
      KokoroModelInstaller.invokeOverride =
          (method) async => const {'directory': ''};
      expect(await KokoroModelInstaller.ensureInstalled(), isNull);
    });
  });

  group('local voice status', () {
    test('probing sets the flag from what the build ships', () async {
      KokoroModelInstaller.invokeOverride =
          (method) async => const {'bundled': true};

      final account = UserAccount();
      await KokoroTtsManager.probe(account);
      expect(account.hasValidKokoroModel, isTrue);

      KokoroModelInstaller.invokeOverride = (method) async => const {};
      await KokoroTtsManager.probe(account);
      expect(account.hasValidKokoroModel, isFalse);
    });

    test('preparing the voice reports OK once it has spoken', () async {
      KokoroModelInstaller.invokeOverride =
          (method) async => const {'bundled': true};
      KokoroTtsEngine.startOverride = () async => _FakeKokoroEngine();

      final account = UserAccount();
      final manager = KokoroTtsManager(userAccount: account);
      addTearDown(manager.dispose);

      await manager.checkConnection();
      expect(manager.status, ConnectionStatus.ok);
      expect(account.hasValidKokoroModel, isTrue);
    });

    test('a missing model explains where to put it', () async {
      KokoroModelInstaller.invokeOverride = (method) async => const {};
      KokoroTtsEngine.startOverride = () async => null;

      final account = UserAccount()..hasValidKokoroModel = true;
      final manager = KokoroTtsManager(userAccount: account);
      addTearDown(manager.dispose);

      await manager.checkConnection();
      expect(manager.status, ConnectionStatus.error);
      expect(manager.lastError, contains('assets'));
      expect(account.hasValidKokoroModel, isFalse);
    });

    test('a silent engine is not reported as working', () async {
      KokoroModelInstaller.invokeOverride =
          (method) async => const {'bundled': true};
      KokoroTtsEngine.startOverride =
          () async => _FakeKokoroEngine(wav: Uint8List(0));

      final account = UserAccount();
      final manager = KokoroTtsManager(userAccount: account);
      addTearDown(manager.dispose);

      await manager.checkConnection();
      expect(manager.status, ConnectionStatus.error);
      expect(account.hasValidKokoroModel, isFalse);
    });
  });

  group('audio duration', () {
    test('is read back from the encoded wav', () {
      // Used to tell a narration that was cut off from one whose text simply
      // ended where it sounded like it ended.
      final oneSecond = encodeWav(Float32List(24000), 24000);
      expect(wavDuration(oneSecond).inMilliseconds, 1000);

      final half = encodeWav(Float32List(12000), 24000);
      expect(wavDuration(half).inMilliseconds, 500);

      // A non-standard rate is taken from the header, not assumed.
      final slower = encodeWav(Float32List(16000), 16000);
      expect(wavDuration(slower).inMilliseconds, 1000);
    });

    test('an empty result has no duration', () {
      expect(wavDuration(encodeWav(Float32List(0), 24000)), Duration.zero);
      expect(wavDuration(Uint8List(0)), Duration.zero);
    });
  });

  group('wav encoding', () {
    test('writes a header audioplayers can read', () {
      final wav = encodeWav(Float32List.fromList([0, 0.5, -0.5]), 24000);
      final bytes = ByteData.view(wav.buffer);

      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(bytes.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(bytes.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(bytes.getUint32(24, Endian.little), 24000);
      expect(bytes.getUint16(34, Endian.little), 16, reason: '16-bit');
      // Header plus two bytes per sample, declared in both length fields.
      expect(wav.length, 44 + 6);
      expect(bytes.getUint32(40, Endian.little), 6);
      expect(bytes.getUint32(4, Endian.little), 36 + 6);
    });

    test('samples keep their sign and scale', () {
      final wav = encodeWav(Float32List.fromList([0, 1.0, -1.0]), 24000);
      final bytes = ByteData.view(wav.buffer);

      expect(bytes.getInt16(44, Endian.little), 0);
      expect(bytes.getInt16(46, Endian.little), 32767);
      expect(bytes.getInt16(48, Endian.little), -32767);
    });

    test('an overshooting sample is clamped, not wrapped', () {
      // Letting 1.2 overflow int16 would wrap to a large negative value and
      // click audibly in the middle of narration.
      final wav = encodeWav(Float32List.fromList([1.2, -1.4]), 24000);
      final bytes = ByteData.view(wav.buffer);

      expect(bytes.getInt16(44, Endian.little), 32767);
      expect(bytes.getInt16(46, Endian.little), -32767);
    });

    test('an empty result is still a valid file', () {
      final wav = encodeWav(Float32List(0), 24000);
      expect(wav.length, 44);
      expect(ByteData.view(wav.buffer).getUint32(40, Endian.little), 0);
    });
  });
}

/// Runs one synthesis through the real provider and returns what the engine
/// was asked for.
Future<_SynthesisRequest> _synthesizeWith({
  Gender? voiceGender,
  SpeakingSpeed? speakingSpeed,
}) async {
  final engine = _FakeKokoroEngine();
  KokoroTtsEngine.resetForTesting();
  KokoroTtsEngine.startOverride = () async => engine;

  final provider = KokoroTtsProvider(
    UserAccount(voiceGender: voiceGender, speakingSpeed: speakingSpeed)
      ..hasValidKokoroModel = true,
  );
  await provider.synthesize('breathe');
  return engine.requests.single;
}

class _SynthesisRequest {
  final String text;
  final int speakerId;
  final double speed;

  const _SynthesisRequest({
    required this.text,
    required this.speakerId,
    required this.speed,
  });
}

class _FakeKokoroEngine implements KokoroSynthesizer {
  final Uint8List wav;
  final void Function()? onShutdown;
  final requests = <_SynthesisRequest>[];

  _FakeKokoroEngine({Uint8List? wav, this.onShutdown})
      : wav = wav ?? Uint8List.fromList(const [1, 2, 3, 4]);

  @override
  Future<void> shutdown() async => onShutdown?.call();

  @override
  Future<Uint8List> synthesize({
    required String text,
    required int speakerId,
    required double speed,
  }) async {
    requests.add(
      _SynthesisRequest(text: text, speakerId: speakerId, speed: speed),
    );
    return wav;
  }
}
