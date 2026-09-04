import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class AuthRepository {
  final FirebaseAuth _firebaseAuth;
  bool _googleInitialized = false;

  AuthRepository({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  Future<UserCredential?> signInWithGoogle() async {
    try {
      debugPrint('🔐 [AuthRepo] Starting Google Sign-In...');

      // google_sign_in v7 uses a singleton instance that must be initialized
      if (!_googleInitialized) {
        debugPrint('🔐 [AuthRepo] Initializing GoogleSignIn instance...');
        await GoogleSignIn.instance.initialize(
          // Web Client ID from google-services.json (client_type: 3)
          serverClientId: '553429085126-1t31qa84ll53obi10rootrk5psv20j96.apps.googleusercontent.com',
        );
        _googleInitialized = true;
        debugPrint('🔐 [AuthRepo] GoogleSignIn initialized.');
      }

      // Try silent sign-in first, fallback to interactive
      debugPrint('🔐 [AuthRepo] Attempting lightweight authentication...');
      GoogleSignInAccount? googleUser =
          await GoogleSignIn.instance.attemptLightweightAuthentication();

      if (googleUser == null) {
        debugPrint('🔐 [AuthRepo] Lightweight auth returned null, launching interactive sign-in...');
        googleUser = await GoogleSignIn.instance.authenticate();
      }

      debugPrint('🔐 [AuthRepo] Got Google account: ${googleUser.email}');

      // In v7, authentication is a synchronous getter returning idToken only
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      debugPrint('🔐 [AuthRepo] idToken present: ${googleAuth.idToken != null}');

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      debugPrint('🔐 [AuthRepo] Signing in to Firebase...');
      final result = await _firebaseAuth.signInWithCredential(credential);
      debugPrint('✅ [AuthRepo] Firebase sign-in success: ${result.user?.email}');
      return result;
    } catch (e, stackTrace) {
      debugPrint('❌ [AuthRepo] Google Sign-In failed: $e');
      debugPrint('📋 [AuthRepo] StackTrace: $stackTrace');
      throw Exception('Failed to sign in with Google: $e');
    }
  }

  Future<UserCredential?> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login();

      if (result.status == LoginStatus.success) {
        final OAuthCredential credential = FacebookAuthProvider.credential(
          result.accessToken!.tokenString,
        );

        return await _firebaseAuth.signInWithCredential(credential);
      } else if (result.status == LoginStatus.cancelled) {
        // User canceled the sign-in
        return null;
      } else {
        throw Exception('Failed to sign in with Facebook: ${result.message}');
      }
    } catch (e) {
      throw Exception('Failed to sign in with Facebook: $e');
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _firebaseAuth.signOut(),
      GoogleSignIn.instance.signOut(),
      FacebookAuth.instance.logOut(),
    ]);
  }
}
