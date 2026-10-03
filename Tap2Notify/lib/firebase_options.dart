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
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCshTqGrUlW1XbUuHfiK03JQqz8zbN8a4Y',
    appId: '1:1082574746898:web:f86797d1f1291f28462fcb',
    messagingSenderId: '1082574746898',
    projectId: 'tab2notify',
    authDomain: 'tab2notify.firebaseapp.com',
    databaseURL: 'https://tab2notify-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'tab2notify.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCshTqGrUlW1XbUuHfiK03JQqz8zbN8a4Y',
    appId: '1:1082574746898:android:f86797d1f1291f28462fcb',
    messagingSenderId: '1082574746898',
    projectId: 'tab2notify',
    authDomain: 'tab2notify.firebaseapp.com',
    databaseURL: 'https://tab2notify-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'tab2notify.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCshTqGrUlW1XbUuHfiK03JQqz8zbN8a4Y',
    appId: '1:1082574746898:ios:f86797d1f1291f28462fcb',
    messagingSenderId: '1082574746898',
    projectId: 'tab2notify',
    authDomain: 'tab2notify.firebaseapp.com',
    databaseURL: 'https://tab2notify-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'tab2notify.firebasestorage.app',
    iosBundleId: 'com.example.tab2notify',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCshTqGrUlW1XbUuHfiK03JQqz8zbN8a4Y',
    appId: '1:1082574746898:ios:f86797d1f1291f28462fcb',
    messagingSenderId: '1082574746898',
    projectId: 'tab2notify',
    authDomain: 'tab2notify.firebaseapp.com',
    databaseURL: 'https://tab2notify-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'tab2notify.firebasestorage.app',
    iosBundleId: 'com.example.tab2notify',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCshTqGrUlW1XbUuHfiK03JQqz8zbN8a4Y',
    appId: '1:1082574746898:web:f86797d1f1291f28462fcb',
    messagingSenderId: '1082574746898',
    projectId: 'tab2notify',
    authDomain: 'tab2notify.firebaseapp.com',
    databaseURL: 'https://tab2notify-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'tab2notify.firebasestorage.app',
  );
}
