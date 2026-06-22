import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  // 👇 Trage hier später deine eigene UID ein, sobald du sie kennst
  static const String kAdminUid = 'NOCH-NICHT-BEKANNT';

  Future<void> init() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    if (kDebugMode) {
      debugPrint('🔑 Firebase UID: ${auth.currentUser?.uid}');
    }
  }

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  bool get isAdmin => currentUid == kAdminUid;
}