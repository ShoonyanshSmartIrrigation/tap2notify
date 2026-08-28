import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// Top-level background message handler for FCM
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

class FCMService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> initialize() async {
    try {
      // Request permission for push notifications
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted push notification permission');
      }

      // Set background messaging handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Subscribe to topics for hotel managers
      await _fcm.subscribeToTopic('hotel_managers');
      await _fcm.subscribeToTopic('service_requests');

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Received foreground FCM message: ${message.notification?.title}');
      });

      // Token
      String? token = await _fcm.getToken();
      debugPrint('FCM Token: $token');
    } catch (e) {
      debugPrint('Error initializing FCM: $e');
    }
  }
}
