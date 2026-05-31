import 'package:flutter/material.dart';
import 'drawer_page.dart';

class DebugInfoPage extends DrawerPage {
  const DebugInfoPage({super.key});

  @override
  String get label => "Debug Info";

  @override
  IconData get icon => Icons.bug_report_outlined;

  @override
  IconData get selectedIcon => Icons.bug_report;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("Debug Info"),
    );
  }
}
