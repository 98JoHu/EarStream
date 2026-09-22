import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../configs/overall_config.dart';
import 'elevenlabs_api.dart';
import 'kokoro_model_installer.dart';
import 'kokoro_tts_engine.dart';
import 'tencent_tts_client.dart';
import 'user_account.dart';

enum ConnectionStatus { missing, checking, error, ok }

/// Verifies one cloud service without allowing an obsolete request to update
/// state after credentials change or this manager is disposed.
abstract class ConnectionManager extends ChangeNotifier {
  @protected
  final UserAccount userAccount;

  ConnectionManager({required this.userAccount});

  ConnectionStatus _status = ConnectionStatus.missing;
  ConnectionStatus get status => _status;

  String? _lastError;
  String? get lastError => _lastError;

  int _requestRevision = 0;
  bool _isDisposed = false;

  void markUnverified() {
    _requestRevision++;
    if (_isDisposed) return;
    invalidateUserCredentials();
    _status = ConnectionStatus.missing;
    _lastError = null;
    notifyListeners();
  }

  Future<void> checkConnection() async {
    if (_isDisposed) return;
    final requestRevision = ++_requestRevision;
    _status = ConnectionStatus.checking;
    _lastError = null;
    notifyListeners();

    try {
      final result = await verifyCredentials();
      if (!_isCurrent(requestRevision)) return;
      updateUser(result);
      if (!_isCurrent(requestRevision)) return;
      _status = ConnectionStatus.ok;
      notifyListeners();
    } catch (error, stackTrace) {
      if (!_isCurrent(requestRevision)) return;
      invalidateUserCredentials();
      debugPrint('Connection check failed: $error');
      debugPrint('$stackTrace');
      _status = ConnectionStatus.error;
      _lastError = error.toString();
      notifyListeners();
    }
  }

  bool _isCurrent(int revision) => !_isDisposed && revision == _requestRevision;

  @protected
  Future<Object?> verifyCredentials();

  @protected
  void updateUser(Object? result);

  @protected
  void invalidateUserCredentials();

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _requestRevision++;
    super.dispose();
  }
}

class DeepseekManager extends ConnectionManager {
  DeepseekManager({required super.userAccount});

  @override
  Future<Object?> verifyCredentials() async {
    if (userAccount.deepseekApiKey?.trim().isEmpty ?? true) {
      throw Exception('Deepseek API key cannot be empty.');
    }

    final response = await http.get(
      Uri.parse(
        '${OverallMeditationConfig.deepseekApiBaseUrl}'
        '${OverallMeditationConfig.deepseekBalancePath}',
      ),
      headers: {
        'Authorization': 'Bearer ${userAccount.deepseekApiKey}',
      },
    ).timeout(OverallMeditationConfig.credentialCheckTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Deepseek API rejected key (Code: ${response.statusCode})',
      );
    }

    return jsonDecode(response.body);
  }

  @override
  void updateUser(Object? result) {
    userAccount.hasValidDeepseekKey = true;
  }

  @override
  void invalidateUserCredentials() {
    userAccount.hasValidDeepseekKey = false;
  }
}

class ElevenLabsManager extends ConnectionManager {
  ElevenLabsManager({required super.userAccount});

  @override
  Future<Object?> verifyCredentials() async {
    if (userAccount.elevenLabsApiKey?.trim().isEmpty ?? true) {
      throw Exception('ElevenLabs API key cannot be empty.');
    }

    final response = await http.get(
      Uri.parse('${OverallMeditationConfig.elevenLabsApiBaseUrl}/v1/voices'),
      headers: {
        'xi-api-key': '${userAccount.elevenLabsApiKey}',
      },
    ).timeout(OverallMeditationConfig.credentialCheckTimeout);
    if (response.statusCode != 200) {
      throw ElevenLabsApiException.fromResponse(response);
    }

    return jsonDecode(response.body);
  }

  @override
  void updateUser(Object? result) {
    final response = result as Map<String, dynamic>;
    final voices = response['voices'] as List;
    final availableVoices = voices
        .map(
          (voice) => (
            voice: voice['name'] as String,
            id: voice['voice_id'] as String,
          ),
        )
        .toList();

    userAccount.hasValidElevenLabsKey = true;
    userAccount.availableElevenLabsVoices = availableVoices;
    final selectedVoiceId = userAccount.elevenLabsVoiceId;
    if (selectedVoiceId != null &&
        !availableVoices.any((voice) => voice.id == selectedVoiceId)) {
      userAccount.elevenLabsVoiceId = null;
    }
  }

  @override
  void invalidateUserCredentials() {
    userAccount.hasValidElevenLabsKey = false;
  }
}

/// Prepares the on-device Kokoro voice and reports whether it is usable.
///
/// There are no credentials to check here. "Verifying" means unpacking the
/// bundled model if it is not already in app storage, loading it, and
/// synthesizing one short line — which is the only way to find out that the
/// local voice will actually speak when a session asks it to. The first run
/// copies roughly 340 MB out of the APK and takes noticeably longer than a
/// cloud key check; later runs only reload the model.
class KokoroTtsManager extends ConnectionManager {
  KokoroTtsManager({required super.userAccount});

  /// Sets [UserAccount.hasValidKokoroModel] from whether this build ships the
  /// model at all, without unpacking it.
  ///
  /// Cheap enough to run when the in-app opens, so the local voice can be
  /// selected without visiting the API Keys page first.
  static Future<void> probe(UserAccount userAccount) async {
    userAccount.hasValidKokoroModel = await KokoroModelInstaller.isBundled();
  }

  @override
  Future<Object?> verifyCredentials() async {
    if (!KokoroModelInstaller.isSupported) {
      throw Exception(
        'The on-device voice is only available in the Android build.',
      );
    }

    final engine = await KokoroTtsEngine.shared();
    if (engine == null) {
      final platformError = KokoroModelInstaller.lastPlatformError;
      throw Exception(
        'No bundled Kokoro model was found. See the in-app README for how to '
        'add it to android/app/src/main/assets.'
        '${platformError == null ? '' : ' Platform reported: $platformError'}',
      );
    }

    final wav = await engine.synthesize(
      text: OverallMeditationConfig.kokoroCredentialCheckText,
      speakerId: userAccount.voiceGender == Gender.male
          ? OverallMeditationConfig.kokoroMaleSpeakerId
          : OverallMeditationConfig.kokoroFemaleSpeakerId,
      speed: OverallMeditationConfig.kokoroMediumSpeechRate,
    );
    if (wav.isEmpty) {
      throw Exception('The local voice produced no audio.');
    }
    return wav.length;
  }

  @override
  void updateUser(Object? result) {
    userAccount.hasValidKokoroModel = true;
  }

  @override
  void invalidateUserCredentials() {
    userAccount.hasValidKokoroModel = false;
  }
}

class TencentTtsManager extends ConnectionManager {
  TencentTtsManager({required super.userAccount});

  @override
  Future<Object?> verifyCredentials() async {
    if (userAccount.tencentSecretId?.trim().isEmpty ?? true) {
      throw Exception('Tencent SecretId cannot be empty.');
    }
    if (userAccount.tencentSecretKey?.trim().isEmpty ?? true) {
      throw Exception('Tencent SecretKey cannot be empty.');
    }

    final client = TencentTtsClient();
    try {
      return await client.synthesize(
        text: 'Connection test.',
        secretId: userAccount.tencentSecretId!,
        secretKey: userAccount.tencentSecretKey!,
        region: userAccount.tencentTtsRegion,
        voiceType: userAccount.voiceGender == Gender.male
            ? OverallMeditationConfig.tencentPremiumMaleVoiceType
            : OverallMeditationConfig.tencentPremiumFemaleVoiceType,
        speed: OverallMeditationConfig.tencentCredentialCheckSpeechRate,
      );
    } finally {
      client.dispose();
    }
  }

  @override
  void updateUser(Object? result) {
    userAccount.hasValidTencentKey = true;
  }

  @override
  void invalidateUserCredentials() {
    userAccount.hasValidTencentKey = false;
  }
}
