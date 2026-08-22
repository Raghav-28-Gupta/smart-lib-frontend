import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/ui/ui_controller.dart';
import 'package:smartlib_frontend/core/ui/ui_state.dart';

void main() {
  test('askReturnLoan opens a returnLoan dialog request, closeDialog clears it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(uiControllerProvider.notifier);

    notifier.askReturnLoan('loan1');
    expect(container.read(uiControllerProvider).dialog?.kind, DialogKind.returnLoan);
    expect(container.read(uiControllerProvider).dialog?.targetId, 'loan1');

    notifier.closeDialog();
    expect(container.read(uiControllerProvider).dialog, isNull);
  });

  test('confirmDialog invokes the registered callback then closes the dialog', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(uiControllerProvider.notifier);
    String? confirmedId;
    notifier.onConfirmReturnLoan = (id) => confirmedId = id;

    notifier.askReturnLoan('loan1');
    await notifier.confirmDialog();

    expect(confirmedId, 'loan1');
    expect(container.read(uiControllerProvider).dialog, isNull);
  });

  test('showToast sets the toast message', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(uiControllerProvider.notifier);
    notifier.showToast('Returned.');
    expect(container.read(uiControllerProvider).toast, 'Returned.');
  });
}
