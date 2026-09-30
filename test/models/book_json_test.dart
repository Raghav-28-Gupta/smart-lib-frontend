// test/models/book_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/models/book.dart';
import '../support/fixtures.dart';

void main() {
  test('parses GET /books/:id, ignoring fields the model has no use for', () {
    // The payload also carries isbn and publishedYear.
    final book = Book.fromJson(fixture('book_by_id') as Map<String, dynamic>);
    expect(book.id, 'b1');
    expect(book.title, 'Introduction to Algorithms');
    expect(book.author, 'Cormen, Leiserson, Rivest & Stein');
    expect(book.genre, 'Algorithms');
    expect(book.description, startsWith('The standard reference'));
    expect(book.totalCopies, 4);
    expect(book.availableCopies, 1);
    expect(book.waitlistCount, 0);
  });

  test('parses every book in GET /books/search', () {
    final books = (fixture('books_search') as List)
        .map((j) => Book.fromJson(j as Map<String, dynamic>))
        .toList();
    expect(books, hasLength(12));
    // b2 is the seeded fully-borrowed title with a waitlist.
    final b2 = books.singleWhere((b) => b.id == 'b2');
    expect(b2.availableCopies, 0);
    expect(b2.waitlistCount, 2);
  });

  test('maps a null genre and description to empty strings', () {
    // No seeded book has nulls here, but BookDto types both as nullable, and
    // the detail screen renders genre in a Chip unconditionally.
    final book = Book.fromJson(const {
      'id': 'x1',
      'isbn': '000',
      'title': 'Untitled',
      'author': 'Anon',
      'genre': null,
      'description': null,
      'publishedYear': null,
      'totalCopies': 1,
      'availableCopies': 1,
      'waitlistCount': 0,
    });
    expect(book.genre, '');
    expect(book.description, '');
  });

  group('coverPalette', () {
    test('is derived from the id, pinned so it cannot drift across platforms', () {
      // Code-unit sum mod 3. Pinning concrete ids guards against a switch to
      // String.hashCode, which Dart does not guarantee is stable between
      // platforms -- web and Android would render different covers.
      Book withId(String id) => Book(
          id: id, title: 't', author: 'a', genre: 'g', description: 'd',
          totalCopies: 1, availableCopies: 1, waitlistCount: 0);
      expect(withId('b1').coverPalette, CoverPalette.accent);
      expect(withId('b2').coverPalette, CoverPalette.accent2);
      expect(withId('b3').coverPalette, CoverPalette.neutral);
    });

    test('varies across the seeded catalog', () async {
      final books = await MockBookRepository().search();
      expect(books.map((b) => b.coverPalette).toSet(), CoverPalette.values.toSet());
    });
  });
}
