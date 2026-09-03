import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import features
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/authentication/presentation/login/login_screen.dart';
import '../../features/authentication/presentation/signup/signup_screen.dart';
import '../../features/authentication/presentation/forgot_password/forgot_password_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/waiter/presentation/waiter_login_screen.dart';
import '../../features/waiter/presentation/waiter_dashboard_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (BuildContext context, GoRouterState state) async {
      final path = state.uri.path;

      // Allow splash screen without interception
      if (path == '/splash') return null;

      bool isManagerLoggedIn = false;
      try {
        isManagerLoggedIn = FirebaseAuth.instance.currentUser != null;
      } catch (_) {}

      // Check persisted Waiter floor session
      bool isWaiterLoggedIn = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        isWaiterLoggedIn = prefs.containsKey('active_waiter_session') &&
            (prefs.getString('active_waiter_session')?.isNotEmpty ?? false);
      } catch (_) {}

      // 1. Guard Manager Dashboard
      if (path == '/dashboard') {
        if (!isManagerLoggedIn) {
          return '/login';
        }
        return null;
      }

      // 2. Guard Waiter Dashboard
      if (path == '/waiter-dashboard') {
        if (!isWaiterLoggedIn) {
          return '/login';
        }
        return null;
      }

      // 3. Prevent logged in users from hitting login pages accidentally
      if (path == '/login') {
        if (isManagerLoggedIn) return '/dashboard';
        if (isWaiterLoggedIn) return '/waiter-dashboard';
      }

      if (path == '/manager-login' && isManagerLoggedIn) {
        return '/dashboard';
      }

      if (path == '/signup' && isManagerLoggedIn) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const WaiterLoginScreen(),
      ),
      GoRoute(
        path: '/waiter-dashboard',
        builder: (context, state) => const WaiterDashboardScreen(),
      ),
      GoRoute(
        path: '/manager-login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
    ],
  );
}

