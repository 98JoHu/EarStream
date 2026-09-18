import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_wearable/apps/meditation_app/model/hr_hrv_processor.dart';
import 'package:open_wearable/apps/meditation_app/model/tencent_tts_client.dart';
import 'package:open_wearable/apps/meditation_app/model/user_account.dart';

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
