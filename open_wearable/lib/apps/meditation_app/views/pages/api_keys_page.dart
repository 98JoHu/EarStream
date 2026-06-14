import 'package:flutter/material.dart';
import '../../model/user_account.dart';
import 'drawer_page.dart';
import '../../widgets/status_field.dart';
import '../../widgets/secret_field.dart';

class ApiKeysPage extends StatefulWidget implements DrawerPage {
  final UserAccount userAccount;
  const ApiKeysPage({super.key, required this.userAccount});

  @override
  String get label => "API Keys";

  @override
  IconData get icon => Icons.key_outlined;

  @override
  IconData get selectedIcon => Icons.key;

  @override
  State<ApiKeysPage> createState() => _ApiKeysPageState();
}

class _ApiKeysPageState extends State<ApiKeysPage> {
  late final DeepseekManager _deepseekManager;
  late final ElevenLabsManager _elevenLabsManager;

  @override
  void initState() {
    super.initState();
    _deepseekManager = DeepseekManager(userAccount: widget.userAccount);
    _elevenLabsManager = ElevenLabsManager(userAccount: widget.userAccount);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Service Credentials',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Keys saved here take effect at runtime for EarStream. The bundled .env file remains a fallback source, but it cannot be edited safely from the UI at runtime.',
                style: TextStyle(color: Colors.grey[700], height: 1.4),
              ),
              const SizedBox(height: 24),
              StatusField(
                connectionManager: _deepseekManager,
                neighbourWidget: SecretField(
                  title: "Deepseek API Key",
                  description:
                      "Provide a Deepseek API key to enable personal stress-adaptive session generation. Keys are stored only on this device.",
                  onChanged: (value) =>
                      widget.userAccount.deepseekApiKey = value,
                  initialValue: widget.userAccount.deepseekApiKey ?? '',
                ),
              ),
              const SizedBox(height: 24),
              StatusField(
                connectionManager: _elevenLabsManager,
                neighbourWidget: SecretField(
                  title: "ElevenLabs API Key",
                  description:
                      "Provide an ElevenLabs API key to enable voice synthesis features. Keys are stored only on this device.",
                  onChanged: (value) =>
                      widget.userAccount.elevenLabsApiKey = value,
                  initialValue: widget.userAccount.elevenLabsApiKey ?? '',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
