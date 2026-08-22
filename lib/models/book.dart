import '../core/theme/smartlib_theme.dart';

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
    required this.coverPalette,
  });

  final String id;
  final String title;
  final String author;
  final String genre;
  final String description;
  final int totalCopies;
  final int availableCopies;
  final int waitlistCount;
  final CoverPalette coverPalette;

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
        coverPalette: coverPalette,
      );
}
