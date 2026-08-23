// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/bookings/booking_flow_screen.dart';
import '../../features/bookings/bookings_screen.dart';
import '../../features/catalog/book_detail_screen.dart';
import '../../features/catalog/search_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/loans/loans_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/recommendations/recommendations_screen.dart';
import '../ui/confirm_dialog.dart';
import '../ui/toast_overlay.dart';

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider.select((s) => s.loggedIn), (prev, next) {
      if (prev != next) notifyListeners();
    });
  }
}

const _tabPaths = ['/home', '/search', '/loans', '/bookings', '/profile'];
const _tabIcons = [Icons.home, Icons.search, Icons.menu_book, Icons.event, Icons.person];
const _tabLabels = ['Home', 'Search', 'Loans', 'Bookings', 'Profile'];

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(authControllerProvider).loggedIn;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const AuthScreen()),
      ShellRoute(
        builder: (context, state, child) => _AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
          GoRoute(path: '/loans', builder: (context, state) => const LoansScreen()),
          GoRoute(path: '/bookings', builder: (context, state) => const BookingsScreen()),
          GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
        ],
      ),
      GoRoute(path: '/book/:id', builder: (context, state) => BookDetailScreen(bookId: state.pathParameters['id']!)),
      GoRoute(path: '/booking/new', builder: (context, state) => const BookingFlowScreen()),
      GoRoute(path: '/recommendations', builder: (context, state) => const RecommendationsScreen()),
    ],
  );
});

class _AppShell extends StatelessWidget {
  const _AppShell({required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final index = _tabPaths.indexOf(location).clamp(0, _tabPaths.length - 1);
    return Scaffold(
      body: Stack(children: [child, const ConfirmDialogHost(), const ToastHost()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabPaths[i]),
        destinations: [for (var i = 0; i < _tabPaths.length; i++) NavigationDestination(icon: Icon(_tabIcons[i]), label: _tabLabels[i])],
      ),
    );
  }
}
