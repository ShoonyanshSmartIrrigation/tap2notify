import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/firebase_auth_service.dart';
import '../../../core/services/firebase_realtime_service.dart';
import '../domain/user_model.dart';

class AuthRepository {
  final FirebaseAuthService _authService;
  final FirebaseRealtimeService _dbService;

  AuthRepository(this._authService, this._dbService);

  Stream<User?> get authStateChanges => _authService.authStateChanges;
  User? get currentUser => _authService.currentUser;

  Future<UserModel> signUp({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final cred = await _authService.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = UserModel(
      uid: cred.user!.uid,
      fullName: fullName,
      email: email,
      phone: phone,
      role: 'manager',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _dbService.createUserProfile(user);
    return user;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _authService.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (cred.user != null) {
      try {
        final profile = await _dbService.getUserProfile(cred.user!.uid);
        if (profile == null) {
          final fallbackUser = UserModel(
            uid: cred.user!.uid,
            fullName: cred.user!.displayName ?? email.split('@').first,
            email: email,
            phone: cred.user!.phoneNumber ?? '',
            role: 'manager',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
          await _dbService.createUserProfile(fallbackUser);
        }
      } catch (e) {
        // Log error without failing sign in
      }
    }

    return cred;
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    await _authService.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _authService.signOut();
  }

  Future<UserModel?> getCurrentUserProfile() async {
    final user = _authService.currentUser;
    if (user != null) {
      return await _dbService.getUserProfile(user.uid);
    }
    return null;
  }

  Stream<UserModel?> get currentUserProfileStream {
    return _authService.authStateChanges.asyncExpand((user) {
      if (user == null) {
        return Stream.value(null);
      }
      return _dbService.getUserProfileStream(user.uid);
    });
  }
}
