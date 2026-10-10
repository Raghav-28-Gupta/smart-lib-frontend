// test/app_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/ui/ui_controller.dart';
import 'package:smartlib_frontend/main.dart';
import 'support/mock_overrides.dart';

void main() {
  testWidgets('toasts show on screens outside the tab shell', (tester) async {
    // The book detail and booking flow screens are pushed over the shell, so
    // a toast host inside the shell would sit underneath them. The login
    // screen is outside the shell too, which makes it a convenient witness.
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SmartLibApp()));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsWidgets);

    container.read(uiControllerProvider.notifier).showToast("Can't reach the library server.");
    await tester.pump();
    expect(find.text("Can't reach the library server."), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // let it clear
    expect(find.text("Can't reach the library server."), findsNothing);
  });
}
