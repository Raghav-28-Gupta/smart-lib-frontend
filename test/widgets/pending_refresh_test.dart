// test/widgets/pending_refresh_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/widgets/pending_refresh.dart';

void main() {
  Widget host({required bool active, required VoidCallback onTick}) =>
      PendingRefresh(active: active, onTick: onTick, child: const SizedBox());

  testWidgets('checks once right after opening, then every 30 seconds while something is pending', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(host(active: true, onTick: () => ticks++));
    expect(ticks, 1);
    await tester.pump(const Duration(seconds: 29));
    expect(ticks, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 2);
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 3);
  });

  testWidgets('does not check on opening when nothing is pending', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(host(active: false, onTick: () => ticks++));
    await tester.pump(const Duration(minutes: 2));
    expect(ticks, 0);
  });

  testWidgets('stops when nothing is pending, and starts again when something is', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(host(active: true, onTick: () => ticks++));
    expect(ticks, 1);
    await tester.pumpWidget(host(active: false, onTick: () => ticks++));
    await tester.pump(const Duration(minutes: 2));
    expect(ticks, 1);
    await tester.pumpWidget(host(active: true, onTick: () => ticks++));
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 2);
  });

  testWidgets('something becoming pending after opening is not checked at once, only after the interval', (tester) async {
    // That happens right after the student requests; the request itself just
    // answered, so an immediate check would be a needless second fetch.
    var ticks = 0;
    await tester.pumpWidget(host(active: false, onTick: () => ticks++));
    await tester.pumpWidget(host(active: true, onTick: () => ticks++));
    await tester.pump();
    expect(ticks, 0);
    await tester.pump(const Duration(seconds: 29));
    expect(ticks, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 1);
  });

  testWidgets('stops when the screen goes away', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(host(active: true, onTick: () => ticks++));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(ticks, 1);
  });
}
