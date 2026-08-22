import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui_state.dart';

class UiController extends Notifier<UiState> {
  void Function(String loanId)? onConfirmReturnLoan;
  void Function(String bookingId)? onConfirmCancelBooking;

  @override
  UiState build() => const UiState();

  void askReturnLoan(String loanId) => state = state.copyWith(dialog: DialogRequest(kind: DialogKind.returnLoan, targetId: loanId));
  void askCancelBooking(String bookingId) => state = state.copyWith(dialog: DialogRequest(kind: DialogKind.cancelBooking, targetId: bookingId));
  void showReliabilityInfo() => state = state.copyWith(dialog: const DialogRequest(kind: DialogKind.reliabilityInfo));
  void closeDialog() => state = state.copyWith(clearDialog: true);

  Future<void> confirmDialog() async {
    final dialog = state.dialog;
    if (dialog == null) return;
    if (dialog.kind == DialogKind.returnLoan && dialog.targetId != null) {
      onConfirmReturnLoan?.call(dialog.targetId!);
      state = state.copyWith(clearDialog: true, toast: 'Returned.');
    } else if (dialog.kind == DialogKind.cancelBooking && dialog.targetId != null) {
      onConfirmCancelBooking?.call(dialog.targetId!);
      state = state.copyWith(clearDialog: true, toast: 'Booking canceled.');
    } else {
      state = state.copyWith(clearDialog: true);
    }
  }

  void showToast(String message) => state = state.copyWith(toast: message);
  void clearToast() => state = state.copyWith(clearToast: true);
}

final uiControllerProvider = NotifierProvider<UiController, UiState>(UiController.new);
