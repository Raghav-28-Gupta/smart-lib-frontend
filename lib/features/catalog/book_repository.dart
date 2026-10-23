import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../models/book.dart';

const kGenres = [
  'All',
  'Data Structures',
  'Algorithms',
  'Operating Systems',
  'Databases',
  'Networks',
  'AI',
  'Software Eng.',
  'Fiction',
  'Non-fiction',
];

// No borrow() here: borrowing is a request a librarian approves, which
// BorrowRequestRepository owns. Likewise, joining the waitlist belongs to
// WaitlistRepository.
abstract class BookRepository {
  Future<List<Book>> search({String query = '', String genre = 'All'});

  /// Null when no such book exists.
  Future<Book?> getById(String id);
}

class HttpBookRepository implements BookRepository {
  HttpBookRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Book>> search({String query = '', String genre = 'All'}) async {
    final q = query.trim();
    final res = await guardApi(() => _dio.get<List<dynamic>>('/books/search', queryParameters: {
          if (q.isNotEmpty) 'q': q,
          if (genre != 'All') 'genre': genre,
        }));
    return res.data!.map((j) => Book.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<Book?> getById(String id) async {
    try {
      final res = await guardApi(() => _dio.get<Map<String, dynamic>>('/books/${Uri.encodeComponent(id)}'));
      return Book.fromJson(res.data!);
    } on ApiException catch (e) {
      // The detail screen has a "no such book" state for null; anything else
      // propagates so the screen can offer Retry.
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}

const _seedBooks = [
  Book(
      id: 'b1',
      title: 'Introduction to Algorithms',
      author: 'Cormen, Leiserson, Rivest & Stein',
      genre: 'Algorithms',
      description:
          'The standard reference on algorithm design and analysis — sorting, graph algorithms, dynamic programming, and NP-completeness, with rigorous proofs throughout.',
      totalCopies: 4,
      availableCopies: 1,
      waitlistCount: 0),
  Book(
      id: 'b2',
      title: 'Operating System Concepts',
      author: 'Silberschatz, Galvin & Gagne',
      genre: 'Operating Systems',
      description:
          'Process management, memory management, file systems, and concurrency — the core operating systems course text.',
      totalCopies: 3,
      availableCopies: 0,
      waitlistCount: 2),
  Book(
      id: 'b3',
      title: 'Database System Concepts',
      author: 'Silberschatz, Korth & Sudarshan',
      genre: 'Databases',
      description:
          'The relational model, SQL, normalization, transaction processing, and query optimization.',
      totalCopies: 5,
      availableCopies: 2,
      waitlistCount: 0),
  Book(
      id: 'b4',
      title: 'Computer Networks',
      author: 'Andrew S. Tanenbaum',
      genre: 'Networks',
      description:
          'A layer-by-layer treatment of network architecture, from the physical layer up through applications.',
      totalCopies: 3,
      availableCopies: 1,
      waitlistCount: 0),
  Book(
      id: 'b5',
      title: 'Data Structures and Algorithms in Java',
      author: 'Robert Lafore',
      genre: 'Data Structures',
      description:
          'Core data structures — trees, graphs, hash tables — built up from first principles with working Java code.',
      totalCopies: 6,
      availableCopies: 3,
      waitlistCount: 0),
  Book(
      id: 'b6',
      title: 'Design Patterns',
      author: 'Gamma, Helm, Johnson & Vlissides',
      genre: 'Software Eng.',
      description:
          'The classic catalog of object-oriented design patterns, from the Gang of Four.',
      totalCopies: 2,
      availableCopies: 0,
      waitlistCount: 0),
  Book(
      id: 'b7',
      title: 'Artificial Intelligence: A Modern Approach',
      author: 'Russell & Norvig',
      genre: 'AI',
      description:
          'A comprehensive survey of AI, from search and logic through machine learning.',
      totalCopies: 3,
      availableCopies: 1,
      waitlistCount: 0),
  Book(
      id: 'b8',
      title: 'Clean Code',
      author: 'Robert C. Martin',
      genre: 'Software Eng.',
      description:
          'Practical guidance on writing maintainable code, with before-and-after refactoring examples.',
      totalCopies: 4,
      availableCopies: 2,
      waitlistCount: 0),
  Book(
      id: 'b9',
      title: 'The Midnight Library',
      author: 'Matt Haig',
      genre: 'Fiction',
      description:
          'A novel about all the lives you could have lived, told through a library between life and death.',
      totalCopies: 2,
      availableCopies: 1,
      waitlistCount: 0),
  Book(
      id: 'b10',
      title: 'Project Hail Mary',
      author: 'Andy Weir',
      genre: 'Fiction',
      description:
          "A lone astronaut wakes with no memory of his mission — or that humanity's survival depends on it.",
      totalCopies: 3,
      availableCopies: 0,
      waitlistCount: 4),
  Book(
      id: 'b11',
      title: 'Sapiens',
      author: 'Yuval Noah Harari',
      genre: 'Non-fiction',
      description:
          'A sweeping account of how Homo sapiens came to dominate the planet.',
      totalCopies: 2,
      availableCopies: 1,
      waitlistCount: 0),
  Book(
      id: 'b12',
      title: 'Atomic Habits',
      author: 'James Clear',
      genre: 'Non-fiction',
      description:
          'A practical framework for building good habits and breaking bad ones.',
      totalCopies: 3,
      availableCopies: 2,
      waitlistCount: 0),
];

class MockBookRepository implements BookRepository {
  final List<Book> _books = List.of(_seedBooks);

  @override
  Future<List<Book>> search({String query = '', String genre = 'All'}) async {
    final q = query.trim().toLowerCase();
    return _books.where((b) {
      final matchesGenre = genre == 'All' || b.genre == genre;
      final matchesQuery = q.isEmpty ||
          b.title.toLowerCase().contains(q) ||
          b.author.toLowerCase().contains(q);
      return matchesGenre && matchesQuery;
    }).toList();
  }

  @override
  Future<Book?> getById(String id) async {
    for (final b in _books) {
      if (b.id == id) return b;
    }
    return null;
  }
}

final bookRepositoryProvider = Provider<BookRepository>((ref) => HttpBookRepository(ref.watch(apiClientProvider)));
