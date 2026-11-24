import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api_exception.dart';
import '../../models/return_report.dart';
import 'ui_state.dart';

class UiController extends Notifier<UiState> {
  // Registered by the screens that own the data; awaited, so the outcome can
  // be reported -- they used to be fire-and-forget, which made every return
  // and cancellation look successful.
  Future<void> Function(String loanId, ReturnReport? report)? onConfirmReturnLoan;
  Future<void> Function(String bookingId)? onConfirmCancelBooking;

  @override
  UiState build() => const UiState();

  void askReturnLoan(String loanId) => state = state.copyWith(dialog: DialogRequest(kind: DialogKind.returnLoan, targetId: loanId));
  void askCancelBooking(String bookingId) => state = state.copyWith(dialog: DialogRequest(kind: DialogKind.cancelBooking, targetId: bookingId));
  void showReliabilityInfo() => state = state.copyWith(dialog: const DialogRequest(kind: DialogKind.reliabilityInfo));
  void closeDialog() => state = state.copyWith(clearDialog: true);

  Future<void> confirmDialog() async {
    final dialog = state.dialog;
    if (dialog == null) return;
    // Closed straight away; the outcome arrives as a toast once the server
    // has answered.
    state = state.copyWith(clearDialog: true);
    final id = dialog.targetId;
    if (id == null) return;
    switch (dialog.kind) {
      case DialogKind.cancelBooking:
        final action = onConfirmCancelBooking;
        if (action != null) await attempt(() => action(id), success: 'Booking canceled.');
      case DialogKind.returnLoan: // confirms through confirmReturnLoan, which carries the report
      case DialogKind.reliabilityInfo:
        break;
    }
  }

  /// Confirms the open Return dialog, with the student's [report] of a problem with
  /// the copy when they made one (the dialog only offers a valid one). Closed straight
  /// away like the other dialogs; the toast follows the server's answer: "Returned.",
  /// or a thank-you for the report, or the server's reason if it refused (the report
  /// is saved together with the return, so a refusal saved neither).
  Future<void> confirmReturnLoan(ReturnReport? report) async {
    final dialog = state.dialog;
    if (dialog == null || dialog.kind != DialogKind.returnLoan) return;
    state = state.copyWith(clearDialog: true);
    final id = dialog.targetId;
    final action = onConfirmReturnLoan;
    if (id == null || action == null) return;
    await attempt(
      () => action(id, report),
      success: report == null ? 'Returned.' : 'Returned. Thanks for the report.',
    );
  }

  /// Runs a user-initiated server action and reports the outcome: [success]
  /// as a toast if it worked, the server's own message if it was refused.
  /// Returns the failure, or null on success, so callers can react to it.
  ///
  /// An expired session gets no toast -- the user is already on their way to
  /// the login screen, which says so. Anything that isn't an API failure is a
  /// bug, and propagates rather than being dressed up as a message.
  Future<ApiException?> attempt(Future<void> Function() action, {String? success}) async {
    try {
      await action();
    } on UnauthorizedException catch (e) {
      return e;
    } on ApiException catch (e) {
      showToast(e.message);
      return e;
    }
    if (success != null) showToast(success);
    return null;
  }

  void showToast(String message) => state = state.copyWith(toast: message);
  void clearToast() => state = state.copyWith(clearToast: true);
}

final uiControllerProvider = NotifierProvider<UiController, UiState>(UiController.new);
