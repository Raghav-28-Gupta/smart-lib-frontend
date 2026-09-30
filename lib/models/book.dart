import 'package:json_annotation/json_annotation.dart';
import '../core/theme/smartlib_theme.dart';

part 'book.g.dart';

@JsonSerializable(createToJson: false)
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.genre,
    required this.description,
    required this.totalCopies,
    required this.availableCopies,
    required this.waitlistCount,
  });

  factory Book.fromJson(Map<String, dynamic> json) => _$BookFromJson(json);

  final String id;
  final String title;
  final String author;

  // Nullable in the backend's BookDto, but the UI renders both
  // unconditionally (genre in a Chip), so null becomes '' at the boundary
  // rather than widening the type for every consumer.
  @JsonKey(defaultValue: '')
  final String genre;
  @JsonKey(defaultValue: '')
  final String description;

  final int totalCopies;
  final int availableCopies;
  final int waitlistCount;

  /// UI-only -- the backend has no palette. Derived from the id so a given
  /// book always gets the same cover everywhere. Deliberately a code-unit
  /// sum rather than `String.hashCode`, which Dart doesn't guarantee is
  /// stable across platforms (web and Android would disagree).
  CoverPalette get coverPalette {
    final sum = id.codeUnits.fold<int>(0, (acc, unit) => acc + unit);
    return CoverPalette.values[sum % CoverPalette.values.length];
  }

  String get initial => title.isNotEmpty ? title[0].toUpperCase() : '?';

  Book copyWith({int? availableCopies, int? waitlistCount}) => Book(
        id: id,
        title: title,
        author: author,
        genre: genre,
        description: description,
        totalCopies: totalCopies,
        availableCopies: availableCopies ?? this.availableCopies,
        waitlistCount: waitlistCount ?? this.waitlistCount,
      );
}
