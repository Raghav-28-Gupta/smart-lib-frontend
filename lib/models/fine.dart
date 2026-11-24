import 'package:json_annotation/json_annotation.dart';
import 'json_converters.dart';

part 'fine.g.dart';

/// What the student sees of a fine's state. The backend never says `pending`:
/// a fine nobody has touched is `outstanding`. [unknown] stands in for a status
/// this version doesn't know, so one new value never fails the whole list.
enum FineStatus { outstanding, adjusted, paid, waived, unknown }

/// Why the fine was written. [unknown] stands in for a reason this version
/// doesn't know.
enum FineReason {
  overdue,
  @JsonValue('no_show')
  noShow,
  lost,
  unknown,
}

/// Where the student's dispute of a fine stands. [open] waits for a librarian;
/// the other three are the answer: the fine was waived, lowered, or left as it
/// was. [unknown] stands in for a status this version doesn't know.
enum DisputeStatus { open, waived, adjusted, upheld, unknown }

/// The student's one dispute of a fine (the backend allows a single one, ever),
/// open or answered. The fine's own `status` is separate and unchanged by it.
@JsonSerializable(createToJson: false)
class FineDispute {
  const FineDispute({required this.status, this.note});

  factory FineDispute.fromJson(Map<String, dynamic> json) => _$FineDisputeFromJson(json);

  @JsonKey(unknownEnumValue: DisputeStatus.unknown)
  final DisputeStatus status;

  /// The librarian's resolution note: null while the dispute is open, and when
  /// they gave none.
  final String? note;
}

/// One of the student's fines, from GET /fines/me.
@JsonSerializable(createToJson: false)
class Fine {
  const Fine({
    required this.id,
    required this.reason,
    required this.item,
    required this.amount,
    required this.originalAmount,
    required this.status,
    required this.date,
    this.note,
    this.dispute,
  });

  factory Fine.fromJson(Map<String, dynamic> json) => _$FineFromJson(json);

  final String id;

  @JsonKey(unknownEnumValue: FineReason.unknown)
  final FineReason reason;

  /// The book's title (overdue, lost) or the resource's name (no-show); empty
  /// when the fine names neither.
  final String item;

  /// What is owed now, in whole rupees. Lower than [originalAmount] when a
  /// librarian lowered or waived the fine.
  final double amount;

  /// What the fine was before it was lowered; equal to [amount] otherwise.
  final double originalAmount;

  @JsonKey(unknownEnumValue: FineStatus.unknown)
  final FineStatus status;

  /// When the fine was written.
  @JsonKey(fromJson: localDateTime)
  final DateTime date;

  /// The librarian's reason for lowering or waiving the fine. It stays after the
  /// fine is paid, and is null when the fine was never adjusted.
  final String? note;

  /// The student's dispute of this fine, or null when they never disputed it (or
  /// the server is older than the disputes). Once there is one the fine can't be
  /// disputed again, whatever became of it.
  final FineDispute? dispute;

  bool get wasAdjusted => originalAmount != amount;

  /// This fine with [dispute] on it: what the card shows the moment the server accepts
  /// the student's dispute, until its own list says so. Nothing else about the fine
  /// changes (a disputed fine is still owed).
  Fine withDispute(FineDispute dispute) => Fine(
        id: id, reason: reason, item: item, amount: amount, originalAmount: originalAmount,
        status: status, date: date, note: note, dispute: dispute,
      );
}

/// GET /fines/me: the newest fines (at most 50) and what is still owed over all of them.
@JsonSerializable(createToJson: false)
class FinesSummary {
  const FinesSummary({required this.fines, required this.outstandingTotal});

  factory FinesSummary.fromJson(Map<String, dynamic> json) => _$FinesSummaryFromJson(json);

  final List<Fine> fines;

  /// Outstanding plus adjusted amounts, in whole rupees.
  final double outstandingTotal;
}
