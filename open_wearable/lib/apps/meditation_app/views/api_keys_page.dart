import 'package:flutter/material.dart';
import 'drawer_page.dart';

class ApiKeysPage extends DrawerPage {
  const ApiKeysPage({super.key});

  @override
  String get label => "API Keys";

  @override
  IconData get icon => Icons.key_outlined;

  @override
  IconData get selectedIcon => Icons.key;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("API Keys"),
    );
  }
}
