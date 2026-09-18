import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../model/user_account.dart';
import '../model/tencent_tts_client.dart';
import '../model/elevenlabs_api.dart';

enum Status { missing, checking, error, ok }

class StatusField extends StatelessWidget {
  final Widget? neighbourWidget;
  final ConnectionManager connectionManager;
  const StatusField({
    super.key,
    this.neighbourWidget,
    required this.connectionManager,
  });

  Color get color {
    switch (connectionManager.status) {
      case Status.missing:
        return Colors.grey;
      case Status.checking:
        return Colors.blue;
      case Status.error:
        return Colors.red;
      case Status.ok:
        return Colors.green;
    }
  }

  String get statusText {
    switch (connectionManager.status) {
      case Status.missing:
        return "Not set";
      case Status.checking:
        return "Checking...";
      case Status.error:
        return "Error";
      case Status.ok:
        return "OK";
    }
  }

  String get description {
    switch (connectionManager.status) {
      case Status.missing:
        return "Credentials have not been verified for the current settings.";
      case Status.checking:
        return "Checking the service connection. This may take a few seconds.";
      case Status.error:
        return connectionManager.lastError ??
            "The service check failed. Please review the credentials and region, then try again.";
      case Status.ok:
        return "The current credentials and settings were accepted.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        neighbourWidget ?? const SizedBox.shrink(),
        if (neighbourWidget != null) const SizedBox(height: 8),
        ListenableBuilder(
          listenable: connectionManager,
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "Current Source",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: connectionManager.checkConnection,
                    child: const Text("Check Connection"),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

abstract class ConnectionManager extends ChangeNotifier {
  @protected
  final UserAccount userAccount;
  ConnectionManager({required this.userAccount});
  Status _status = Status.missing;
  Status get status => _status;
  String? _lastError;
  String? get lastError => _lastError;

  void markUnverified() {
    _status = Status.missing;
    _lastError = null;
    notifyListeners();
  }

  Future<void> checkConnection() async {
    _status = Status.checking;
    _lastError = null;
    notifyListeners();

    try {
      final dynamic result = await verifyCredentials();
      await updateUser(result);
      _status = Status.ok;
      notifyListeners();
    } catch (e) {
      print("Connection check failed: $e");
      _status = Status.error;
      _lastError = e.toString();
      notifyListeners();
    }
  }

  @protected
  Future<dynamic> verifyCredentials();

  @protected
  Future<void> updateUser(dynamic result);
}

class DeepseekManager extends ConnectionManager {
  DeepseekManager({required super.userAccount});

  @override
  Future<dynamic> verifyCredentials() async {
    userAccount.hasValidDeepseekKey = false;
    if (userAccount.deepseekApiKey?.isEmpty ?? true) {
      throw Exception('Deepseek API key cannot be empty.');
    }

    final response = await http.get(
      Uri.parse('https://api.deepseek.com/user/balance'),
      headers: {
        'Authorization': 'Bearer ${userAccount.deepseekApiKey}',
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      userAccount.hasValidDeepseekKey = false; // Mark the key as invalid
      throw Exception(
        'Deepseek API rejected key (Code: ${response.statusCode})',
      );
    }

    return json.decode(response.body);
  }

  @override
  Future<void> updateUser(dynamic result) async {
    // Flag current API key as valid
    userAccount.hasValidDeepseekKey = true;
  }
}

class ElevenLabsManager extends ConnectionManager {
  ElevenLabsManager({required super.userAccount});

  @override
  Future<dynamic> verifyCredentials() async {
    userAccount.hasValidElevenLabsKey = false;
    if (userAccount.elevenLabsApiKey?.isEmpty ?? true) {
      throw Exception('ElevenLabs API key cannot be empty.');
    }

    final response = await http.get(
      Uri.parse('https://api.elevenlabs.io/v1/voices'),
      headers: {
        'xi-api-key': '${userAccount.elevenLabsApiKey}',
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      userAccount.hasValidElevenLabsKey = false; // Mark the key as invalid
      throw ElevenLabsApiException.fromResponse(response);
    }

    return json.decode(response.body);
  }

  @override
  Future<void> updateUser(dynamic result) async {
    final voices = result["voices"] as List;
    userAccount.hasValidElevenLabsKey = true; // Mark the key as valid
    userAccount.availableElevenLabsVoices = voices
        .map(
          (voice) =>
              (voice: voice["name"] as String, id: voice["voice_id"] as String),
        )
        .toList();
  }
}

class TencentTtsManager extends ConnectionManager {
  TencentTtsManager({required super.userAccount});

  @override
  Future<dynamic> verifyCredentials() async {
    userAccount.hasValidTencentKey = false;
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
            ? tencentPremiumMaleVoiceType
            : tencentPremiumFemaleVoiceType,
        speed: 0,
      );
    } finally {
      client.dispose();
    }
  }

  @override
  Future<void> updateUser(dynamic _) async {
    userAccount.hasValidTencentKey = true;
  }
}
