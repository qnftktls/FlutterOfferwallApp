// Generated Firebase options (auto-fetched from the Firebase project).
// ignore_for_file: lines_longer_than_80_chars

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for the Rewards Hub app.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyApxiGnbuwtrfp-I-0Cwpich02YjKcqUdQ',
    appId: '1:594360818152:web:89cd2182cd84b7ad212c5d',
    messagingSenderId: '594360818152',
    projectId: 'flutter-offerwall-app',
    authDomain: 'flutter-offerwall-app.firebaseapp.com',
    storageBucket: 'flutter-offerwall-app.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCqlTA3ZPmtL_UXSxYahxHCImSZt8MD_x4',
    appId: '1:594360818152:android:ebec7110aacc4dbb212c5d',
    messagingSenderId: '594360818152',
    projectId: 'flutter-offerwall-app',
    storageBucket: 'flutter-offerwall-app.firebasestorage.app',
  );
}
