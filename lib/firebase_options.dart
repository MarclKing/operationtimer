import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Keine Firebase-Konfiguration für diese Plattform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyClr_hoW-3xw0E5IPCUXFEaBOdY1O_eYeU',
    appId: '1:594306195787:web:eda4d26e4e42a0309f08ce',
    messagingSenderId: '594306195787',
    projectId: 'optimes-707',
    authDomain: 'optimes-707.firebaseapp.com',
    storageBucket: 'optimes-707.firebasestorage.app',
    measurementId: 'G-3870W5QXP8',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyACeQuVl2qKy_hAQ5NUqaDW7yDUHwLJeOE',
    appId: '1:594306195787:android:2864dbd8feb8c0379f08ce',
    messagingSenderId: '594306195787',
    projectId: 'optimes-707',
    storageBucket: 'optimes-707.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDylk7OZrFyFIiPX4GVHByseJ3jDp2txCo',
    appId: '1:594306195787:ios:07fcb2e580414fcc9f08ce',
    messagingSenderId: '594306195787',
    projectId: 'optimes-707',
    storageBucket: 'optimes-707.firebasestorage.app',
    iosBundleId: 'de.marcel.optimes',
  );
}