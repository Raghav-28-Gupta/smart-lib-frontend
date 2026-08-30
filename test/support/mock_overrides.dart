// test/support/mock_overrides.dart
//
// Every repository provider is `Provider<Interface>`, defaulting today to a
// `Mock*` implementation. Once the HTTP implementations land (T11+), those
// defaults flip to real network calls. Any test that constructs a bare
// `ProviderScope()`/`ProviderContainer()` without overrides is implicitly
// relying on "mock-by-default" -- once the flip happens, that test would
// attempt a real socket connection instead.
//
// This file is the fix: apply `mockRepositoryOverrides()` to every bare
// container so tests stay pinned to the mocks regardless of what the
// production default is. A function (not a const list) because each
// container needs its own fresh Mock instances -- sharing one across tests
// would leak state between them.
import 'package:smartlib_frontend/features/auth/auth_repository.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/profile/profile_repository.dart';
import 'package:smartlib_frontend/features/recommendations/recommendation_repository.dart';

/// Overrides all six repository providers to (fresh, by default) mocks.
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
  ];
}
