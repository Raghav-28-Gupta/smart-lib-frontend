// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/smartlib_theme.dart';

void main() {
  runApp(const ProviderScope(child: SmartLibApp()));
}

class SmartLibApp extends ConsumerWidget {
  const SmartLibApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SmartLib',
      theme: buildSmartLibTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
