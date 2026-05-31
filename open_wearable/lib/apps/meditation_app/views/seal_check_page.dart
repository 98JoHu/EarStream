import 'package:flutter/material.dart';
import 'drawer_page.dart';

class SealCheckPage extends DrawerPage {
  const SealCheckPage({super.key});

  @override
  String get label => "OpenEarable 2.0 Seal Check";

  @override
  IconData get icon => Icons.verified_outlined;

  @override
  IconData get selectedIcon => Icons.verified;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("OpenEarable 2.0 Seal Check"),
    );
  }
}
