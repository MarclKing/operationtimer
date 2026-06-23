import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const Set<String> kAdminUids = {
    'NAQsP0ri7AZxWlAyAX1fc2x0Qrv1',
    'paqEWajROwZA90thq4MRfg4FB9s1',
    'cQgn2r909jTlLLGzFaQ17ylQfeB3',
    'OTIjqy74oNW4IZoV8m7dXEOobTu2',
    'B9oAkNcqEYNRuJPZBnjWhmX0sew2',
    'OCASs8NpKZSpiLKywWoS0v4kpuy2',
  };

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

  bool get isAdmin => kAdminUids.contains(currentUid);
}