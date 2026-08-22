import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/health/health_check_screen.dart';

void main() {
  runApp(const ProviderScope(child: SmartLibApp()));
}

class SmartLibApp extends StatelessWidget {
  const SmartLibApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartLib',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HealthCheckScreen(),
    );
  }
}
