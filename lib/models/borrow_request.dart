import 'package:json_annotation/json_annotation.dart';
import 'json_converters.dart';

part 'borrow_request.g.dart';

/// GET /borrow-requests/me sends pending requests and those declined or
/// expired in the last 7 days; approved and withdrawn ones drop off (the loan
/// appears instead). [unknown] stands in for a status this version doesn't
/// know, so one new value never fails the whole list.
enum BorrowRequestStatus { pending, approved, declined, expired, cancelled, unknown }

/// A student's request to borrow a book, waiting for a librarian.
@JsonSerializable(createToJson: false)
class BorrowRequest {
  const BorrowRequest({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.status,
    required this.requestedAt,
    required this.expiresAt,
    this.decidedAt,
    this.declineReason,
  });

  factory BorrowRequest.fromJson(Map<String, dynamic> json) => _$BorrowRequestFromJson(json);

  final String id;
  final String bookId;
  final String bookTitle;

  @JsonKey(unknownEnumValue: BorrowRequestStatus.unknown)
  final BorrowRequestStatus status;

  @JsonKey(fromJson: localDateTime)
  final DateTime requestedAt;

  /// When the held copy goes back to the shelf if no librarian has decided.
  @JsonKey(fromJson: localDateTime)
  final DateTime expiresAt;

  @JsonKey(fromJson: localDateTimeOrNull)
  final DateTime? decidedAt;

  /// Set only on a declined request, and only if the librarian gave one.
  final String? declineReason;
}
