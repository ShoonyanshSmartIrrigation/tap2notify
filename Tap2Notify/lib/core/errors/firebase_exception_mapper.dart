import 'package:firebase_auth/firebase_auth.dart';

class FirebaseExceptionMapper {
  static String mapAuthException(dynamic error) {
    if (error is FirebaseAuthException) {
      final msg = error.message ?? '';
      if (error.code == 'configuration-not-found' || msg.contains('CONFIGURATION_NOT_FOUND')) {
        return 'Email/Password Sign-In is not enabled in Firebase Console.\n\nPlease enable it in Firebase Console > Authentication > Sign-in method.';
      }

      switch (error.code) {
        case 'user-not-found':
          return 'No manager account found with this email.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'invalid-email':
          return 'The email address is badly formatted.';
        case 'user-disabled':
          return 'This user account has been disabled.';
        case 'email-already-in-use':
          return 'An account already exists for this email address.';
        case 'operation-not-allowed':
          return 'Email/Password sign-in is disabled in Firebase Console. Please enable it in Authentication > Sign-in method.';
        case 'weak-password':
          return 'The password is too weak. Please use at least 8 characters.';
        case 'invalid-credential':
          return 'Invalid login credentials. Please verify your email and password.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        case 'too-many-requests':
          return 'Too many failed attempts. Please try again later.';
        default:
          return error.message ?? 'An unexpected authentication error occurred.';
      }
    }
    
    final errStr = error.toString();
    if (errStr.contains('CONFIGURATION_NOT_FOUND')) {
      return 'Email/Password Sign-In is not enabled in Firebase Console. Please enable it in Firebase Console > Authentication > Sign-in method.';
    }
    if (errStr.toLowerCase().contains('permission_denied') || errStr.toLowerCase().contains('permission-denied')) {
      return 'Realtime Database Permission Denied!\nPlease update your Realtime Database Rules in Firebase Console to allow read/write.';
    }
    
    return errStr;
  }
}
