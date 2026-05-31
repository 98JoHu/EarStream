import 'package:flutter/material.dart';

abstract class DrawerPage extends StatelessWidget {
  const DrawerPage({super.key});

  String get label;
  IconData get icon;
  IconData get selectedIcon;
}
