import 'package:flutter/material.dart';
import 'package:vrc_monitor/widgets/login_page.dart';

class VrcMonitorApp extends StatelessWidget {
  const VrcMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VRChat Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}
