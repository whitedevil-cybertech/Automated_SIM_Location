import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IfsoApp());
}

/// Root Application Widget for IFSO Location Request Management System.
class IfsoApp extends StatelessWidget {
  const IfsoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IFSO Location Request Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}
