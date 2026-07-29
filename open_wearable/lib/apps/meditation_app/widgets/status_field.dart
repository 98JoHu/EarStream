import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../model/user_account.dart';

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
        return "No source selected. Please choose a source to enable stress detection.";
      case Status.checking:
        return "Checking the connection to the source. This may take a few seconds.";
      case Status.error:
        return "Failed to connect to the source. Please check your settings and try again.";
      case Status.ok:
        return "Successfully connected to the source.";
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

  Future<void> checkConnection() async {
    _status = Status.checking;
    notifyListeners();

    try {
      final dynamic result = await verifyCredentials();
      _status = Status.ok;
      notifyListeners();

      await updateUser(result);
    } catch (e) {
      print("Connection check failed: $e");
      _status = Status.error;
      notifyListeners();
    }
  }

  @protected
  Future<dynamic> verifyCredentials();

  @protected
  Future<void> updateUser(dynamic result);
}

class OutlookConnectionManager extends ConnectionManager {
  OutlookConnectionManager({required super.userAccount});

  @override
  Future<dynamic> verifyCredentials() async {
    if (userAccount.outlookSuppressionToken?.isEmpty ?? true) {
      throw Exception('Outlook token cannot be empty.');
    }

    final now = DateTime.now().toUtc();
    final url =
        'https://graph.microsoft.com/v1.0/me/calendarView?startDateTime=${now.toIso8601String()}&endDateTime=${now.add(const Duration(minutes: 1)).toIso8601String()}';

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer ${userAccount.outlookSuppressionToken}',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Outlook API rejected token (Code: ${response.statusCode})',
      );
    }

    // Pass the decoded JSON body forward to the next step
    return json.decode(response.body);
  }

  @override
  Future<void> updateUser(dynamic rawData) async {
    final List events = rawData['value'] ?? [];

    // Check if there's an active meeting that blocks the user's schedule
    bool isCurrentlyInMeeting =
        events.any((event) => event['showAs'] != 'free');

    // Update your local user database or user state object here!
    // Example: currentUser.isMutedByCalendar = isCurrentlyInMeeting;
    print('Outlook Synced. User Busy Status: $isCurrentlyInMeeting');
  }
}

class DeepseekManager extends ConnectionManager {
  DeepseekManager({required super.userAccount});

  @override
  Future<dynamic> verifyCredentials() async {
    if (userAccount.deepseekApiKey?.isEmpty ?? true) {
      throw Exception('Deepseek API key cannot be empty.');
    }

    final response = await http.get(
      Uri.parse('https://api.deepseek.com/user/balance'),
      headers: {
        'Authorization': 'Bearer ${userAccount.deepseekApiKey}',
      },
    );

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
    if (userAccount.elevenLabsApiKey?.isEmpty ?? true) {
      throw Exception('ElevenLabs API key cannot be empty.');
    }

    final response = await http.get(
      Uri.parse('https://api.elevenlabs.io/v1/voices'),
      headers: {
        'xi-api-key': '${userAccount.elevenLabsApiKey}',
      },
    );
    if (response.statusCode != 200) {
      userAccount.hasValidElevenLabsKey = false; // Mark the key as invalid
      throw Exception(
        'ElevenLabs API rejected key (Code: ${response.statusCode})',
      );
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

class DashscopeManager extends ConnectionManager {
  DashscopeManager({required super.userAccount});

  @override
  Future<dynamic> verifyCredentials() async {
    if (userAccount.dashscopeApiKey?.isEmpty ?? true) {
      throw Exception('Dashscope API key cannot be empty.');
    }

    final response = await http.get(
      Uri.parse(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/models',
      ),
      headers: {
        'Authorization': 'Bearer ${userAccount.dashscopeApiKey}',
      },
    );

    if (response.statusCode != 200) {
      userAccount.hasValidDashscopeKey = false; // Mark the key as invalid
      throw Exception(
        'Dashscope API rejected key (Code: ${response.statusCode})',
      );
    }

    return json.decode(response.body);
  }

  @override
  Future<void> updateUser(dynamic result) async {
    // Extract relevant account info from the result and update your user model
    print('Dashscope Synced. Account Info: $result');
    userAccount.hasValidDashscopeKey = true; // Mark the key as valid
  }
}
