import 'package:json_annotation/json_annotation.dart';
import 'json_converters.dart';

part 'loan.g.dart';

enum LoanStatus { normal, overdue }

@JsonSerializable(createToJson: false)
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

  factory Loan.fromJson(Map<String, dynamic> json) => _$LoanFromJson(json);

  final String id;
  final String bookId;

  @JsonKey(name: 'dueAt', fromJson: localDateTime)
  final DateTime dueDate;

  // The backend sends its raw DB status ('active'/'returned') as `status` and
  // the UI-facing one as `frontendStatus`; only the latter maps onto this
  // enum. Overdue is computed server-side at read time, never persisted.
  @JsonKey(name: 'frontendStatus')
  final LoanStatus status;

  final double fineAmount;
  final bool canRenew;
  final String? blockedReason;

  /// Client-only: set after a successful renew so the loans screen can flash
  /// "Renewed". The server has no such concept.
  @JsonKey(includeFromJson: false, includeToJson: false)
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
