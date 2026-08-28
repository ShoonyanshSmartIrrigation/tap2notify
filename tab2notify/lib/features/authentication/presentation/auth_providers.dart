import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/firebase_auth_service.dart';
import '../../../core/services/firebase_realtime_service.dart';
import '../data/auth_repository.dart';
import '../domain/user_model.dart';

final firebaseAuthServiceProvider = Provider<FirebaseAuthService>((ref) {
  return FirebaseAuthService();
});

final firebaseRealtimeServiceProvider = Provider<FirebaseRealtimeService>((ref) {
  return FirebaseRealtimeService();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final authService = ref.watch(firebaseAuthServiceProvider);
  final dbService = ref.watch(firebaseRealtimeServiceProvider);
  return AuthRepository(authService, dbService);
});

final authStateProvider = StreamProvider<User?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.authStateChanges;
});

final currentUserProfileProvider = FutureProvider<UserModel?>((ref) async {
  final repository = ref.watch(authRepositoryProvider);
  return await repository.getCurrentUserProfile();
});
