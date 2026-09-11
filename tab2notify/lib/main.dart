import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/routes/app_router.dart';
import 'core/services/fcm_service.dart';
import 'core/services/shared_preferences_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-load SharedPreferences before runApp to allow synchronous Riverpod initial state
  final sharedPreferences = await SharedPreferences.getInstance();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Initialize FCM push notification service (permissions, channels, background handlers)
    await FCMService().initialize();

    // If an active waiter session exists in SharedPreferences, ensure its FCM token is synced
    final rawWaiter = sharedPreferences.getString('active_waiter_session');
    if (rawWaiter != null && rawWaiter.isNotEmpty) {
      try {
        final map = jsonDecode(rawWaiter) as Map<String, dynamic>;
        final managerPhone =
            map['managerPhone']?.toString() ??
            map['manager_phone']?.toString() ??
            '';
        final waiterId = map['waiterId']?.toString() ?? '';
        if (managerPhone.isNotEmpty && waiterId.isNotEmpty) {
          await FCMService().syncWaiterSession(managerPhone, waiterId);
        }
      } catch (e) {
        debugPrint('Error restoring waiter FCM token: $e');
      }
    } else {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        final phone = authUser.phoneNumber ?? authUser.uid;
        await FCMService().syncManagerSession(phone, authUser.uid);
      }
    }
  } catch (e) {
    debugPrint('Firebase/FCM Initialization Error: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const Tab2NotifyApp(),
    ),
  );
}

class Tab2NotifyApp extends ConsumerWidget {
  const Tab2NotifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Tab2Notify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 350),
      themeAnimationCurve: Curves.easeInOut,
      routerConfig: AppRouter.router,
      builder: (context, child) {
        final Brightness effectiveBrightness = themeMode == ThemeMode.system
            ? MediaQuery.platformBrightnessOf(context)
            : (themeMode == ThemeMode.dark
                  ? Brightness.dark
                  : Brightness.light);
        final ThemeData currentTheme = effectiveBrightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme;

        return AnimatedTheme(
          data: currentTheme,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
