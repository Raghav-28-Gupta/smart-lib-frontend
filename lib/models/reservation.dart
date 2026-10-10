import 'package:json_annotation/json_annotation.dart';
import 'json_converters.dart';

part 'reservation.g.dart';

/// GET /reservations/me only returns live entries, so these are the only two.
enum ReservationStatus {
  @JsonValue('waiting')
  waiting,

  /// The backend's 'fulfilled': a copy came back and is being held for this
  /// student until [Reservation.claimExpiresAt], then passes to the next.
  @JsonValue('fulfilled')
  held,
}

/// A student's place on a book's waitlist.
@JsonSerializable(createToJson: false)
class Reservation {
  const Reservation({
    required this.id,
    required this.bookId,
    required this.status,
    this.queuePosition,
    this.claimExpiresAt,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) => _$ReservationFromJson(json);

  final String id;
  final String bookId;
  final ReservationStatus status;

  /// 1 = next in line. Null once a copy is held.
  final int? queuePosition;

  /// When a held copy passes to the next student. Null while waiting.
  @JsonKey(fromJson: localDateTimeOrNull)
  final DateTime? claimExpiresAt;
}
