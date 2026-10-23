// test/support/mock_overrides.dart
//
// Every repository provider is `Provider<Interface>`, and the production
// defaults are the `Http*` implementations -- so a test that constructs a
// bare `ProviderScope()`/`ProviderContainer()` makes real network calls, and
// reads the real platform keystore through the token store.
//
// Apply `mockRepositoryOverrides()` to every container in a test instead: it
// pins all eight repositories to the `Mock*` test doubles and the token store
// to memory. A function (not a const list) because each container needs its
// own fresh Mock instances -- sharing one across tests would leak state
// between them.
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/auth/auth_repository.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/borrow_requests/borrow_request_repository.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/profile/profile_repository.dart';
import 'package:smartlib_frontend/features/recommendations/recommendation_repository.dart';
import 'package:smartlib_frontend/features/waitlist/waitlist_repository.dart';
import 'fake_token_store.dart';

/// Overrides all eight repository providers to (fresh, by default) mocks, and
/// the token store to in-memory persistence -- so no test reaches the network
/// or a real platform keystore.
///
/// Pass a repository instance for any provider a specific test needs to
/// *substitute* -- e.g. `mockRepositoryOverrides(loans: _CleanLoanRepository())`
/// -- rather than appending a second, competing override for the same
/// provider elsewhere in the same `overrides:` list.
// Riverpod 3 deliberately doesn't export the `Override` type returned by
// `.overrideWith()` (it's a sealed, internal implementation detail) -- every
// call site in this codebase builds its `overrides:` list as an inline
// literal for the same reason. Omitting the return type here lets Dart
// infer it structurally; every `overrides:` parameter still type-checks the
// list this returns.
mockRepositoryOverrides({
  AuthRepository? auth,
  BookRepository? books,
  LoanRepository? loans,
  BookingRepository? bookings,
  ProfileRepository? profile,
  RecommendationRepository? recommendations,
  WaitlistRepository? waitlist,
  BorrowRequestRepository? borrowRequests,
  TokenStore? tokens,
}) {
  return [
    authRepositoryProvider.overrideWith((ref) => auth ?? MockAuthRepository()),
    bookRepositoryProvider.overrideWith((ref) => books ?? MockBookRepository()),
    loanRepositoryProvider.overrideWith((ref) => loans ?? MockLoanRepository()),
    bookingRepositoryProvider.overrideWith((ref) => bookings ?? MockBookingRepository()),
    profileRepositoryProvider.overrideWith((ref) => profile ?? MockProfileRepository()),
    // The real default constructs MockRecommendationRepository from
    // ref.watch(bookRepositoryProvider) -- reproduced here so a caller who
    // only substitutes `books` still gets a recommendation repo wired to
    // that same books override, not a disconnected fresh one.
    recommendationRepositoryProvider.overrideWith(
      (ref) => recommendations ?? MockRecommendationRepository(ref.watch(bookRepositoryProvider)),
    ),
    // Wired to the same books override, so a join's place in line follows
    // that book's waitlist count.
    waitlistRepositoryProvider.overrideWith(
      (ref) => waitlist ?? MockWaitlistRepository(ref.watch(bookRepositoryProvider)),
    ),
    // Wired to the same books override, so a request's title follows it.
    borrowRequestRepositoryProvider.overrideWith(
      (ref) => borrowRequests ?? MockBorrowRequestRepository(ref.watch(bookRepositoryProvider)),
    ),
    tokenStoreProvider.overrideWith((ref) {
      // A store passed in belongs to the test (which may pre-seed or inspect
      // it), so only dispose the ones created here.
      if (tokens != null) return tokens;
      final store = TokenStore(InMemoryTokenPersistence());
      ref.onDispose(store.dispose);
      return store;
    }),
  ];
}
