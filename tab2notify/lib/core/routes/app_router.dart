import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Import features (Placeholders for now)
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/authentication/presentation/login/login_screen.dart';
import '../../features/authentication/presentation/signup/signup_screen.dart';
import '../../features/authentication/presentation/forgot_password/forgot_password_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
    ],
  );
}
