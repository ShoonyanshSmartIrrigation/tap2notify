import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/service_requests/presentation/service_request_providers.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  runApp(
    const ProviderScope(
      child: Tab2NotifyApp(),
    ),
  );
}

class Tab2NotifyApp extends ConsumerStatefulWidget {
  const Tab2NotifyApp({super.key});

  @override
  ConsumerState<Tab2NotifyApp> createState() => _Tab2NotifyAppState();
}

class _Tab2NotifyAppState extends ConsumerState<Tab2NotifyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleServiceProvider).requestPermissionsAndStartScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Tab2Notify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: AppRouter.router,
    );
  }
}
