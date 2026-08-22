enum LoanStatus { normal, overdue }

class Loan {
  const Loan({
    required this.id,
    required this.bookId,
    required this.dueDate,
    required this.status,
    required this.fineAmount,
    required this.canRenew,
    this.blockedReason,
    this.justRenewed = false,
  });

  final String id;
  final String bookId;
  final DateTime dueDate;
  final LoanStatus status;
  final double fineAmount;
  final bool canRenew;
  final String? blockedReason;
  final bool justRenewed;

  Loan copyWith({
    DateTime? dueDate,
    LoanStatus? status,
    double? fineAmount,
    bool? canRenew,
    String? blockedReason,
    bool? justRenewed,
  }) =>
      Loan(
        id: id,
        bookId: bookId,
        dueDate: dueDate ?? this.dueDate,
        status: status ?? this.status,
        fineAmount: fineAmount ?? this.fineAmount,
        canRenew: canRenew ?? this.canRenew,
        blockedReason: blockedReason ?? this.blockedReason,
        justRenewed: justRenewed ?? this.justRenewed,
      );
}
