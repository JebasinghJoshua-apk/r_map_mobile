import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBlje8H5x0l0WoLF-WcTMxHxXzMkWPXDlQ',
    appId: '1:700895122851:android:80395b10ae16e496693616',
    messagingSenderId: '700895122851',
    projectId: 'rmap-60045',
    storageBucket: 'rmap-60045.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDECSScoCgED6o0dLg1erJpdQgwR2g3Kns',
    appId: '1:700895122851:ios:e9c8cc7be20d22e1693616',
    messagingSenderId: '700895122851',
    projectId: 'rmap-60045',
    storageBucket: 'rmap-60045.firebasestorage.app',
    iosBundleId: 'com.example.rMapMobile',
  );
}