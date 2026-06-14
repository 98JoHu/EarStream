import 'package:flutter/material.dart';
import 'drawer_page.dart';
import '../../model/user_account.dart';
import '../../widgets/status_field.dart';
import '../../widgets/secret_field.dart';

class CalendarIntegrationPage extends StatefulWidget implements DrawerPage {
  final UserAccount userAccount;
  const CalendarIntegrationPage({super.key, required this.userAccount});

  @override
  String get label => "Outlook Calendar Integration";

  @override
  IconData get icon => Icons.calendar_today_outlined;

  @override
  IconData get selectedIcon => Icons.calendar_today;

  @override
  State<CalendarIntegrationPage> createState() =>
      _CalendarIntegrationPageState();
}

class _CalendarIntegrationPageState extends State<CalendarIntegrationPage> {
  late final OutlookConnectionManager _connectionManager;

  @override
  void initState() {
    super.initState();
    _connectionManager =
        OutlookConnectionManager(userAccount: widget.userAccount);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Outlook suppression token',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'EarStream polls Microsoft Graph to avoid firing stress prompts during meetings. Tokens are stored only on this device.',
              style: TextStyle(color: Colors.grey[700], height: 1.4),
            ),
            const SizedBox(height: 24),
            StatusField(
              neighbourWidget: SecretField(
                title: "Suppression Token",
                description: "Enter your Outlook suppression token here.",
                onChanged: (value) =>
                    widget.userAccount.outlookSuppressionToken = value,
                initialValue: widget.userAccount.outlookSuppressionToken ?? '',
              ),
              connectionManager: _connectionManager,
            ),
          ],
        ),
      ),
    );
  }
}
