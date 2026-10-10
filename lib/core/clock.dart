// lib/core/clock.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current time, as a provider so screens that depend on the time of day
/// (which booking slots have passed) can be tested at a fixed moment.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
