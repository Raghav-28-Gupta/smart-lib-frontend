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

  bool get wasAdjusted => originalAmount != amount;
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
