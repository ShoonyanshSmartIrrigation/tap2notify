import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';
import '../routes/app_router.dart';
import 'firebase_realtime_service.dart';
import 'notification_audio_service.dart';

/// Top-level background message handler for FCM.
/// Executed by the Android/iOS OS in a separate background isolate when a push arrives
/// while the application is terminated or backgrounded.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
  debugPrint('[FCM BACKGROUND] Received push messageId: ${message.messageId}, data: ${message.data}');
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;
  FirebaseRealtimeService? _cachedDbService;
  FirebaseRealtimeService get _dbService =>
      _cachedDbService ??= FirebaseRealtimeService();

  static const String _prefUserIdKey = 'fcm_session_user_id';
  static const String _prefUserRoleKey = 'fcm_session_role';
  static const String _prefManagerPhoneKey = 'fcm_session_manager_phone';
  static const String _prefLastSyncedTokenKey = 'fcm_last_synced_token';

  StreamSubscription<String>? _tokenRefreshSub;
  String? _currentUserId;
  String? _currentUserRole; // 'waiter' or 'manager'
  String? _currentManagerPhone;
  String? _lastSyncedToken;
  String? _lastHandledMessageId;
  bool _isInitialized = false;

  static const MethodChannel _nativeChannel =
      MethodChannel('tab2notify/native_notifications');

  /// Stream of incoming foreground FCM messages
  final _foregroundMessageController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onForegroundMessage => _foregroundMessageController.stream;

  String? get currentUserId => _currentUserId;
  String? get currentUserRole => _currentUserRole;
  String? get currentManagerPhone => _currentManagerPhone;

  /// Topic builders
  String _waiterTopic(String phone, String waiterId) =>
      'waiter_${FirebaseRealtimeService.sanitizePhone(phone)}_$waiterId';
  String _managerTopic(String phone) =>
      'manager_${FirebaseRealtimeService.sanitizePhone(phone)}';

  /// Initialize FCM permissions, channels, background handler, and tap listeners.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      // 1. Request notification permissions (Android 13+ and iOS)
      final settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

      // 2. Set foreground presentation options
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 3. Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 4. Handle notification tap when app is launched from TERMINATED/KILLED state
      _handleTerminatedAppLaunch();

      // 5. Setup native notification channel for heads-up alerts and local triggers
      _setupNativeNotificationChannel();

      // 6. Handle notification tap when app is in BACKGROUND / MINIMIZED state
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[FCM OPENED] Notification tapped from background: ${message.messageId}');
        if (_isMessageAuthorizedForCurrentSession(message)) {
          _processNotificationTap(message);
        }
      });

      // 7. Handle notification received while app is in FOREGROUND
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM FOREGROUND] Push received in foreground: ${message.notification?.title}');
        if (_isMessageAuthorizedForCurrentSession(message)) {
          _foregroundMessageController.add(message);
          _handleForegroundMessage(message);
        } else {
          debugPrint('[FCM FOREGROUND] Push suppressed: Unauthorized for current session');
        }
      });

      // 8. Restore cached session state from persistent storage
      await _restoreSessionFromStorage();

      // 9. Initial token check and start token rotation listener
      _listenToTokenRefresh();
    } catch (e) {
      debugPrint('[FCM ERROR] Error during FCM initialization: $e');
    }
  }

  /// Restore saved session credentials to ensure active session context survives process death
  Future<void> _restoreSessionFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString(_prefUserIdKey);
      _currentUserRole = prefs.getString(_prefUserRoleKey);
      _currentManagerPhone = prefs.getString(_prefManagerPhoneKey);
      _lastSyncedToken = prefs.getString(_prefLastSyncedTokenKey);
      debugPrint('[FCM SESSION RESTORE] User: $_currentUserId, Role: $_currentUserRole, Phone: $_currentManagerPhone');
    } catch (e) {
      debugPrint('[FCM SESSION RESTORE ERROR] $e');
    }
  }

  /// Persist session metadata in SharedPreferences
  Future<void> _persistSessionToStorage({
    required String userId,
    required String role,
    required String managerPhone,
    required String token,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUserIdKey, userId);
      await prefs.setString(_prefUserRoleKey, role);
      await prefs.setString(_prefManagerPhoneKey, managerPhone);
      await prefs.setString(_prefLastSyncedTokenKey, token);
    } catch (e) {
      debugPrint('[FCM PERSIST ERROR] $e');
    }
  }

  /// Clear session metadata in SharedPreferences
  Future<void> _clearSessionFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefUserIdKey);
      await prefs.remove(_prefUserRoleKey);
      await prefs.remove(_prefManagerPhoneKey);
      await prefs.remove(_prefLastSyncedTokenKey);
    } catch (e) {
      debugPrint('[FCM CLEAR PERSIST ERROR] $e');
    }
  }

  /// Client-side notification authorization gate: verifies that incoming message
  /// matches the currently active user role and ID.
  bool _isMessageAuthorizedForCurrentSession(RemoteMessage message) {
    // If device is currently logged out, strictly reject all push notifications
    if (_currentUserId == null || _currentUserRole == null) {
      debugPrint('[FCM REJECT] Device is logged out. Notification rejected.');
      return false;
    }

    final data = message.data;
    final targetRole = data['targetRole']?.toString() ?? data['role']?.toString();
    final targetUserId = data['targetUserId']?.toString() ??
        data['waiterId']?.toString() ??
        data['waiter_id']?.toString();
    final targetManagerPhone = data['managerPhone']?.toString() ?? data['manager_phone']?.toString();

    // Verify manager phone match if present
    if (targetManagerPhone != null &&
        targetManagerPhone.isNotEmpty &&
        _currentManagerPhone != null &&
        _currentManagerPhone!.isNotEmpty) {
      final cleanTarget = FirebaseRealtimeService.sanitizePhone(targetManagerPhone);
      final cleanCurrent = FirebaseRealtimeService.sanitizePhone(_currentManagerPhone!);
      if (cleanTarget != cleanCurrent) {
        debugPrint('[FCM REJECT] Manager phone mismatch (target: $cleanTarget, current: $cleanCurrent). Rejected.');
        return false;
      }
    }

    // Strict Role Isolation
    if (targetRole != null && targetRole.isNotEmpty) {
      if (targetRole == 'waiter' && _currentUserRole != 'waiter') {
        debugPrint('[FCM REJECT] Waiter notification sent to $_currentUserRole. Rejected.');
        return false;
      }
      if (targetRole == 'manager' && _currentUserRole != 'manager') {
        debugPrint('[FCM REJECT] Manager notification sent to $_currentUserRole. Rejected.');
        return false;
      }
    }

    // Strict Waiter User Isolation
    if (_currentUserRole == 'waiter' && targetUserId != null && targetUserId.isNotEmpty) {
      if (_currentUserId != targetUserId) {
        debugPrint('[FCM REJECT] Notification targeted for Waiter $targetUserId, but device is Waiter $_currentUserId. Rejected.');
        return false;
      }
    }

    return true;
  }

  /// Setup native platform notification channel listeners for instant heads-up alerts
  void _setupNativeNotificationChannel() {
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationTapped') {
        final data = call.arguments;
        final reqId = data is Map ? data['requestId']?.toString() : null;
        debugPrint('[NATIVE NOTIF] Notification tapped with requestId: $reqId');
        if (reqId != null && reqId.isNotEmpty) {
          AppRouter.navigateToRequest(reqId);
        }
      }
    });

    // Check if app was cold-started by tapping a native notification
    _nativeChannel.invokeMethod<String>('getInitialNotificationPayload').then((initialReq) {
      if (initialReq != null && initialReq.isNotEmpty) {
        debugPrint('[NATIVE NOTIF INITIAL] Cold launch via native notification: $initialReq');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 700), () {
            AppRouter.navigateToRequest(initialReq);
          });
        });
      }
    }).catchError((_) {});
  }

  /// Displays a high-priority native OS heads-up notification with sound & vibration
  Future<void> showNativeNotification({
    required String title,
    required String body,
    required String requestId,
    int? tableNumber,
    int? notificationId,
    String? channelId,
    String? sound,
  }) async {
    try {
      final tNum = tableNumber ??
          int.tryParse(requestId.replaceAll(RegExp(r'[^0-9]'), '')) ??
          1;
      await _nativeChannel.invokeMethod('showNotification', {
        'title': title,
        'body': body,
        'requestId': requestId,
        'tableNumber': tNum,
        'notificationId': notificationId ?? tNum,
        'channelId': ?channelId,
        'sound': ?sound,
      });
      debugPrint('[NATIVE NOTIF] Dispatched notification for $requestId (Table $tNum, channel: $channelId)');
    } catch (e) {
      debugPrint('[NATIVE NOTIF ERROR] Failed to display native notification: $e');
    }
  }

  /// Clears an active notification from the system tray
  Future<void> clearNativeNotification(int notificationId) async {
    try {
      await _nativeChannel.invokeMethod('clearNotification', {
        'notificationId': notificationId,
      });
    } catch (_) {}
  }

  /// Process app launch from a completely terminated / killed state
  Future<void> _handleTerminatedAppLaunch() async {
    try {
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null && _isMessageAuthorizedForCurrentSession(initialMessage)) {
        debugPrint('[FCM TERMINATED LAUNCH] App opened via push from terminated state: ${initialMessage.messageId}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 600), () {
            _processNotificationTap(initialMessage);
          });
        });
      }
    } catch (e) {
      debugPrint('[FCM ERROR] Error checking initial message: $e');
    }
  }

  /// Extracts payload parameters and routes to the specific table request
  void _processNotificationTap(RemoteMessage message) {
    if (message.messageId != null && message.messageId == _lastHandledMessageId) {
      debugPrint('[FCM] Duplicate tap ignored for messageId: ${message.messageId}');
      return;
    }
    _lastHandledMessageId = message.messageId;

    final data = message.data;
    final requestId = data['requestId']?.toString() ??
        data['tableId']?.toString() ??
        data['table_id']?.toString() ??
        '';
    final targetWaiterId = data['waiterId']?.toString() ?? data['waiter_id']?.toString();

    debugPrint('[FCM ROUTE] Navigating to request: $requestId (Target Waiter: $targetWaiterId)');

    if (requestId.isNotEmpty) {
      AppRouter.navigateToRequest(requestId, waiterId: targetWaiterId);
    }
  }

  /// Displays an in-app banner with vibration/haptics when an alert arrives in the foreground
  void _handleForegroundMessage(RemoteMessage message) {
    HapticFeedback.heavyImpact();

    final title = message.notification?.title ?? 'New Waiter Request';
    final body = message.notification?.body ?? 'A customer is calling for service!';
    final data = message.data;
    final requestId = data['requestId']?.toString() ?? data['tableId']?.toString() ?? '';
    final waiterId = data['waiterId']?.toString();
    final type = data['type']?.toString();

    // If active user is an authorized WAITER receiving an incoming table request, play audio prompt
    if (_currentUserRole == 'waiter') {
      NotificationAudioService().playIncomingRequestPrompt(tableId: requestId);
    } else if (_currentUserRole == 'manager' && type == 'manager_escalation') {
      NotificationAudioService().playManagerEscalationPrompt(tableId: requestId);
    }

    final context = AppRouter.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFE53935),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: const Color(0xFFFFD54F),
          onPressed: () {
            if (requestId.isNotEmpty) {
              AppRouter.navigateToRequest(requestId, waiterId: waiterId);
            }
          },
        ),
        backgroundColor: const Color(0xFF1E1B26),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: const Color(0xFFE53935).withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
      ),
    );
  }

  /// Listen for FCM token refresh and automatically rotate tokens in RTDB
  void _listenToTokenRefresh() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _fcm.onTokenRefresh.listen((newToken) async {
      debugPrint('[FCM REFRESH] onTokenRefresh triggered with new token');
      final oldToken = _lastSyncedToken ?? '';
      final userId = _currentUserId;
      final role = _currentUserRole;
      final managerPhone = _currentManagerPhone;

      if (userId != null && role != null && managerPhone != null && userId.isNotEmpty) {
        final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
        await _dbService.rotateDeviceFcmToken(
          oldToken: oldToken,
          newToken: newToken,
          userId: userId,
          role: role,
          managerPhone: managerPhone,
          platform: platform,
        );
        _lastSyncedToken = newToken;
        await _persistSessionToStorage(
          userId: userId,
          role: role,
          managerPhone: managerPhone,
          token: newToken,
        );
        debugPrint('[FCM REFRESH] Token rotated successfully for $role $userId');
      }
    });
  }

  /// Register and associate current device's FCM token with active WAITER in RTDB
  Future<void> syncWaiterSession(String managerPhone, String waiterId) async {
    if (waiterId.trim().isEmpty) return;

    // Disassociate previous session if switching accounts on same device
    if (_currentUserId != null && (_currentUserId != waiterId || _currentUserRole != 'waiter')) {
      debugPrint('[FCM SWITCH] Switching from $_currentUserRole $_currentUserId to Waiter $waiterId');
      await unregisterCurrentSession();
    }

    // Idempotency check: Return early if already active and synced for this waiter
    if (_currentUserId == waiterId &&
        _currentUserRole == 'waiter' &&
        _currentManagerPhone == managerPhone &&
        _lastSyncedToken != null) {
      debugPrint('[FCM SESSION] Waiter $waiterId session already active and synced.');
      return;
    }

    _currentManagerPhone = managerPhone;
    _currentUserId = waiterId;
    _currentUserRole = 'waiter';

    try {
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        _lastSyncedToken = token;
        final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

        await _dbService.registerDeviceFcmToken(
          token: token,
          userId: waiterId,
          role: 'waiter',
          managerPhone: managerPhone,
          platform: platform,
        );

        await _persistSessionToStorage(
          userId: waiterId,
          role: 'waiter',
          managerPhone: managerPhone,
          token: token,
        );

        // Topic subscriptions: Subscribe to waiter-specific topic, unsubscribe from manager topic
        await _fcm.subscribeToTopic(_waiterTopic(managerPhone, waiterId));
        await _fcm.unsubscribeFromTopic(_managerTopic(managerPhone));

        debugPrint('[FCM SESSION] Waiter $waiterId registered and subscribed to ${_waiterTopic(managerPhone, waiterId)}');
      }
    } catch (e) {
      debugPrint('[FCM SESSION ERROR] Error registering waiter session: $e');
    }
  }

  /// Register and associate current device's FCM token with authenticated MANAGER in RTDB
  Future<void> syncManagerSession(String managerPhone, String managerUid) async {
    if (managerUid.trim().isEmpty) return;

    // Disassociate previous session if switching accounts on same device
    if (_currentUserId != null && (_currentUserId != managerUid || _currentUserRole != 'manager')) {
      debugPrint('[FCM SWITCH] Switching from $_currentUserRole $_currentUserId to Manager $managerUid');
      await unregisterCurrentSession();
    }

    // Idempotency check: Return early if already active and synced for this manager
    if (_currentUserId == managerUid &&
        _currentUserRole == 'manager' &&
        _currentManagerPhone == managerPhone &&
        _lastSyncedToken != null) {
      debugPrint('[FCM SESSION] Manager $managerUid session already active and synced.');
      return;
    }

    _currentManagerPhone = managerPhone;
    _currentUserId = managerUid;
    _currentUserRole = 'manager';

    try {
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        _lastSyncedToken = token;
        final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

        await _dbService.registerDeviceFcmToken(
          token: token,
          userId: managerUid,
          role: 'manager',
          managerPhone: managerPhone,
          platform: platform,
        );

        await _persistSessionToStorage(
          userId: managerUid,
          role: 'manager',
          managerPhone: managerPhone,
          token: token,
        );

        // Topic subscriptions: Subscribe to manager-specific topic
        await _fcm.subscribeToTopic(_managerTopic(managerPhone));

        debugPrint('[FCM SESSION] Manager $managerUid registered and subscribed to ${_managerTopic(managerPhone)}');
      }
    } catch (e) {
      debugPrint('[FCM SESSION ERROR] Error registering manager session: $e');
    }
  }

  /// Unregister device FCM token and cleanly tear down session upon logout
  Future<void> unregisterCurrentSession() async {
    final userId = _currentUserId;
    final role = _currentUserRole;
    final phone = _currentManagerPhone;
    final token = _lastSyncedToken;

    // 1. Reset memory state immediately to block incoming messages
    _currentUserId = null;
    _currentUserRole = null;
    _currentManagerPhone = null;
    _lastSyncedToken = null;

    // 2. Clear persistent storage
    await _clearSessionFromStorage();

    // 3. Deactivate token in backend RTDB
    if (token != null && token.isNotEmpty && userId != null && role != null) {
      try {
        await _dbService.deactivateDeviceFcmToken(
          token: token,
          userId: userId,
          role: role,
          managerPhone: phone ?? '',
        );
        debugPrint('[FCM LOGOUT] Deactivated backend token for $role $userId');
      } catch (e) {
        debugPrint('[FCM LOGOUT ERROR] Failed to deactivate backend token: $e');
      }
    }

    // 4. Unsubscribe from all topics
    if (phone != null && phone.isNotEmpty) {
      try {
        if (role == 'waiter' && userId != null) {
          await _fcm.unsubscribeFromTopic(_waiterTopic(phone, userId));
        } else if (role == 'manager') {
          await _fcm.unsubscribeFromTopic(_managerTopic(phone));
        }
      } catch (e) {
        debugPrint('[FCM LOGOUT ERROR] Topic unsubscription error: $e');
      }
    }

    // 5. Invalidate the current FCM registration token on this device
    try {
      await _fcm.deleteToken();
      debugPrint('[FCM LOGOUT] Successfully deleted FCM token from device');
    } catch (e) {
      debugPrint('[FCM LOGOUT ERROR] Failed to delete device token: $e');
    }
  }

  /// Backward-compatible alias for waiter token sync
  Future<void> syncWaiterToken(String managerPhone, String waiterId) =>
      syncWaiterSession(managerPhone, waiterId);

  /// Backward-compatible alias for waiter logout
  Future<void> unregisterWaiterToken() => unregisterCurrentSession();
}
