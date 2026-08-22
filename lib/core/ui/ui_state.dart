enum DialogKind { returnLoan, cancelBooking, reliabilityInfo }

class DialogRequest {
  const DialogRequest({required this.kind, this.targetId});
  final DialogKind kind;
  final String? targetId;
}

class UiState {
  const UiState({this.dialog, this.toast});
  final DialogRequest? dialog;
  final String? toast;

  UiState copyWith({DialogRequest? dialog, bool clearDialog = false, String? toast, bool clearToast = false}) =>
      UiState(
        dialog: clearDialog ? null : (dialog ?? this.dialog),
        toast: clearToast ? null : (toast ?? this.toast),
      );
}
