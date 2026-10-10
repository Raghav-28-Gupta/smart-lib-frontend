import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/ui/ui_controller.dart';
import 'package:smartlib_frontend/core/ui/ui_state.dart';

void main() {
  late ProviderContainer container;
  late UiController ui;
  setUp(() {
    container = ProviderContainer();
    ui = container.read(uiControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  String? toast() => container.read(uiControllerProvider).toast;

  test('askReturnLoan opens a returnLoan dialog request, closeDialog clears it', () {
    ui.askReturnLoan('loan1');
    expect(container.read(uiControllerProvider).dialog?.kind, DialogKind.returnLoan);
    expect(container.read(uiControllerProvider).dialog?.targetId, 'loan1');

    ui.closeDialog();
    expect(container.read(uiControllerProvider).dialog, isNull);
  });

  test('showToast sets the toast message', () {
    ui.showToast('Returned.');
    expect(toast(), 'Returned.');
  });

  group('attempt', () {
    test('a success shows the success message and returns no error', () async {
      final error = await ui.attempt(() async {}, success: 'Done.');
      expect(error, isNull);
      expect(toast(), 'Done.');
    });

    test('a refusal shows the server\'s own message', () async {
      final error = await ui.attempt(() async => throw const ConflictException('1 student is waiting for this title.'));
      expect(error, isA<ConflictException>());
      expect(toast(), '1 student is waiting for this title.');
    });

    test('an expired session shows no toast -- the login screen explains it', () async {
      final error = await ui.attempt(() async => throw const UnauthorizedException('Invalid or expired token'));
      expect(error, isA<UnauthorizedException>());
      expect(toast(), isNull);
    });

    test('anything that is not an API failure is a bug, and is not swallowed', () async {
      await expectLater(ui.attempt(() async => throw StateError('bug')), throwsStateError);
    });
  });

  group('confirmDialog', () {
    test('runs the action, closes the dialog, then confirms', () async {
      String? returned;
      ui.onConfirmReturnLoan = (id) async => returned = id;
      ui.askReturnLoan('loan1');
      await ui.confirmDialog();

      expect(returned, 'loan1');
      expect(container.read(uiControllerProvider).dialog, isNull);
      expect(toast(), 'Returned.');
    });

    test('a refused return shows the reason instead of a false "Returned."', () async {
      // The success toast used to fire unconditionally, before the request
      // even finished -- so a server refusal still read as success.
      ui.onConfirmReturnLoan = (id) async => throw const ConflictException('This loan has already been returned.');
      ui.askReturnLoan('loan1');
      await ui.confirmDialog();

      expect(toast(), 'This loan has already been returned.');
      expect(container.read(uiControllerProvider).dialog, isNull);
    });

    test('a refused cancellation shows the reason instead of "Booking canceled."', () async {
      ui.onConfirmCancelBooking = (id) async => throw const ConflictException('This booking cannot be cancelled.');
      ui.askCancelBooking('bk1');
      await ui.confirmDialog();

      expect(toast(), 'This booking cannot be cancelled.');
    });
  });
}
