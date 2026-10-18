import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Result of an auth operation, surfaced to the UI.
class AuthResult {
  const AuthResult({required this.ok, this.error});

  final bool ok;
  final String? error;
}

/// Wraps Firebase Authentication (email/password) with a clean API.
///
/// Also supports a "guest" mode so the app is fully usable without an account.
/// All calls are defensive: if Firebase failed to initialize they degrade to a
/// local session instead of crashing.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  bool _firebaseReady = false;

  /// Whether Firebase Auth is available this run.
  bool get isFirebaseReady => _firebaseReady;

  /// Marks whether Firebase initialized successfully (set from main()).
  void markReady(bool ready) => _firebaseReady = ready;

  final ValueNotifier<AppUser?> user =
      ValueNotifier<AppUser?>(null);

  FirebaseAuth? get _auth {
    if (!_firebaseReady) return null;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  /// Subscribes to Firebase's auth state (call once after Firebase init).
  void bind() {
    final FirebaseAuth? auth = _auth;
    if (auth == null) return;
    auth.authStateChanges().listen((User? u) {
      user.value = u == null
          ? null
          : AppUser(uid: u.uid, email: u.email ?? '', isGuest: false);
    });
  }

  bool get isSignedIn => user.value != null;

  /// Signs in with email + password.
  Future<AuthResult> signIn(String email, String password) async {
    final FirebaseAuth? auth = _auth;
    if (auth == null) {
      // Offline/demo fallback: accept a local guest session.
      user.value = AppUser(uid: 'local', email: email, isGuest: false);
      return const AuthResult(ok: true);
    }
    try {
      final UserCredential cred = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      user.value = AppUser(
        uid: cred.user?.uid ?? '',
        email: cred.user?.email ?? email,
        isGuest: false,
      );
      return const AuthResult(ok: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(ok: false, error: e.message ?? e.code);
    } catch (e) {
      return AuthResult(ok: false, error: e.toString());
    }
  }

  /// Registers a new account with email + password.
  Future<AuthResult> signUp(String email, String password) async {
    final FirebaseAuth? auth = _auth;
    if (auth == null) {
      user.value = AppUser(uid: 'local', email: email, isGuest: false);
      return const AuthResult(ok: true);
    }
    try {
      final UserCredential cred = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      user.value = AppUser(
        uid: cred.user?.uid ?? '',
        email: cred.user?.email ?? email,
        isGuest: false,
      );
      return const AuthResult(ok: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(ok: false, error: e.message ?? e.code);
    } catch (e) {
      return AuthResult(ok: false, error: e.toString());
    }
  }

  /// Sends a password-reset email.
  Future<AuthResult> sendPasswordReset(String email) async {
    final FirebaseAuth? auth = _auth;
    if (auth == null) return const AuthResult(ok: true);
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
      return const AuthResult(ok: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(ok: false, error: e.message ?? e.code);
    }
  }

  /// Continue without an account.
  void continueAsGuest() {
    user.value = const AppUser(uid: 'guest', email: '', isGuest: true);
  }

  Future<void> signOut() async {
    user.value = null;
    try {
      await _auth?.signOut();
    } catch (_) {
      // ignore
    }
  }
}

/// A lightweight user view model used across the UI.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.isGuest,
  });

  final String uid;
  final String email;
  final bool isGuest;

  String get displayName =>
      isGuest ? 'Guest' : (email.isEmpty ? 'User' : email.split('@').first);

  String get initials {
    final String name = displayName;
    if (name.isEmpty) return 'RH';
    final List<String> parts = name.split(RegExp(r'[.@_\s]+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }
}
