// test/features/catalog/http_book_repository_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  (HttpBookRepository, StubHttpAdapter) repo(FutureOr<StubResponse> Function(RequestOptions) respond) {
    final dio = buildApiClient(TokenStore(InMemoryTokenPersistence()));
    final stub = StubHttpAdapter(respond);
    dio.httpClientAdapter = stub;
    return (HttpBookRepository(dio), stub);
  }

  group('search', () {
    test('with no filters sends no query params, and parses the catalog', () async {
      final (books, stub) = repo((_) => StubResponse(200, fixture('books_search')));
      final results = await books.search();
      expect(stub.requests.single.path, '/books/search');
      expect(stub.requests.single.queryParameters, isEmpty);
      expect(results, hasLength(12));
    });

    test('sends the trimmed query and the genre', () async {
      final (books, stub) = repo((_) => const StubResponse(200, <Object>[]));
      await books.search(query: '  clean code ', genre: 'Software Eng.');
      expect(stub.requests.single.queryParameters, {'q': 'clean code', 'genre': 'Software Eng.'});
    });

    test('treats "All" and a blank query as no filter', () async {
      final (books, stub) = repo((_) => const StubResponse(200, <Object>[]));
      await books.search(query: '   ', genre: 'All');
      expect(stub.requests.single.queryParameters, isEmpty);
    });
  });

  group('getById', () {
    test('fetches and parses one book', () async {
      final (books, stub) = repo((_) => StubResponse(200, fixture('book_by_id')));
      final book = await books.getById('b1');
      expect(stub.requests.single.path, '/books/b1');
      expect(book?.title, 'Introduction to Algorithms');
    });

    test('returns null for a book that does not exist', () async {
      // The detail screen renders a "no such book" state for null, so a 404
      // must not become an error screen with a pointless Retry.
      final (books, _) = repo((_) => StubResponse(404, fixture('error_404')));
      expect(await books.getById('does-not-exist'), isNull);
    });

    test('lets any other failure through, so the screen can offer Retry', () async {
      final (books, _) = repo((o) => throw DioException.connectionError(requestOptions: o, reason: 'refused'));
      await expectLater(books.getById('b1'), throwsA(isA<ApiException>()));
    });
  });
}
