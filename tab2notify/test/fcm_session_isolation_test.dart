import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tab2notify/core/services/ble_service.dart';
import 'package:tab2notify/core/services/firebase_realtime_service.dart';
import 'package:tab2notify/features/service_requests/data/service_request_repository.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';

// Mock in-memory database service for testing token registry and isolation rules
class MockFirebaseRealtimeService extends FirebaseRealtimeService {
  final Map<String, Map<String, dynamic>> deviceTokensRegistry = {};
  final Map<String, Map<String, dynamic>> waiterTokensRegistry = {};
  final Map<String, Map<String, dynamic>> managerTokensRegistry = {};

  final StreamController<List<TableModel>> _tablesController =
      StreamController<List<TableModel>>.broadcast();

  void emitTables(List<TableModel> tables) {
    _tablesController.add(tables);
  }

  @override
  Stream<List<TableModel>> getTablesStream({
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    return _tablesController.stream;
  }

  @override
  Future<void> registerDeviceFcmToken({
    required String token,
    required String userId,
    required String role,
    required String managerPhone,
    String platform = 'android',
  }) async {
    final tokenKey = FirebaseRealtimeService.sanitizeTokenKey(token);

    // Disassociate previous owner of this device token
    if (deviceTokensRegistry.containsKey(tokenKey)) {
      final prev = deviceTokensRegistry[tokenKey]!;
      final prevUser = prev['userId']?.toString();
      final prevRole = prev['role']?.toString();
      if (prevUser != null && prevUser != userId) {
        if (prevRole == 'waiter') {
          waiterTokensRegistry[prevUser]?.remove(tokenKey);
        } else if (prevRole == 'manager') {
          managerTokensRegistry[prevUser]?.remove(tokenKey);
        }
      }
    }

    deviceTokensRegistry[tokenKey] = {
      'token': token,
      'tokenKey': tokenKey,
      'userId': userId,
      'role': role,
      'managerPhone': managerPhone,
      'active': true,
    };

    if (role == 'waiter') {
      waiterTokensRegistry.putIfAbsent(userId, () => {})[tokenKey] = {
        'token': token,
        'active': true,
        'role': 'waiter',
      };
    } else if (role == 'manager') {
      managerTokensRegistry.putIfAbsent(userId, () => {})[tokenKey] = {
        'token': token,
        'active': true,
        'role': 'manager',
      };
    }
  }

  @override
  Future<void> deactivateDeviceFcmToken({
    required String token,
    required String userId,
    required String role,
    required String managerPhone,
  }) async {
    final tokenKey = FirebaseRealtimeService.sanitizeTokenKey(token);
    if (deviceTokensRegistry.containsKey(tokenKey)) {
      deviceTokensRegistry[tokenKey]!['active'] = false;
    }
    if (role == 'waiter' && waiterTokensRegistry.containsKey(userId)) {
      waiterTokensRegistry[userId]?.remove(tokenKey);
    } else if (role == 'manager' && managerTokensRegistry.containsKey(userId)) {
      managerTokensRegistry[userId]?.remove(tokenKey);
    }
  }

  @override
  Future<void> rotateDeviceFcmToken({
    required String oldToken,
    required String newToken,
    required String userId,
    required String role,
    required String managerPhone,
    String platform = 'android',
  }) async {
    await deactivateDeviceFcmToken(
      token: oldToken,
      userId: userId,
      role: role,
      managerPhone: managerPhone,
    );
    await registerDeviceFcmToken(
      token: newToken,
      userId: userId,
      role: role,
      managerPhone: managerPhone,
      platform: platform,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FCM Session & Notification Authorization Acceptance Tests', () {
    const channel = MethodChannel('tab2notify/native_notifications');
    final List<MethodCall> nativeCalls = [];
    late MockFirebaseRealtimeService mockDb;
    late BleService bleService;

    setUp(() async {
      nativeCalls.clear();
      SharedPreferences.setMockInitialValues({});
      mockDb = MockFirebaseRealtimeService();
      bleService = BleService();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        nativeCalls.add(methodCall);
        if (methodCall.method == 'showNotification') {
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    // ============================================================
    // Test 1 — Waiter logout
    // Login as Waiter A -> Receive Waiter A notification.
    // Logout Waiter A.
    // Send another notification to Waiter A.
    // Result: the phone MUST NOT receive it.
    // ============================================================
    test('Test 1 — Waiter logout suppresses subsequent notifications', () async {
      // 1. Waiter A logs in
      var repo = ServiceRequestRepository(
        bleService,
        mockDb,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      // Simulate Table 1 calling (Assigned to W001)
      mockDb.emitTables([
        TableModel(
          id: 'table_1',
          tableNumber: 1,
          deviceId: 'device_1',
          status: 'pending',
          flag: 0,
          assignedWaiterId: 'W001',
          waiterName: 'Rahul Sharma (W001)',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(nativeCalls.length, 1, reason: 'Waiter A must receive alert for Table 1');
      expect(nativeCalls.first.arguments['tableNumber'], 1);

      // 2. Waiter A logs out
      repo.dispose();
      await mockDb.deactivateDeviceFcmToken(
        token: 'device_token_phone1',
        userId: 'W001',
        role: 'waiter',
        managerPhone: '9876543210',
      );
      nativeCalls.clear();

      // 3. Customer at Table 1 calls again after logout
      mockDb.emitTables([
        TableModel(
          id: 'table_1',
          tableNumber: 1,
          deviceId: 'device_1',
          status: 'pending',
          flag: 0,
          assignedWaiterId: 'W001',
          waiterName: 'Rahul Sharma (W001)',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

      await Future.delayed(const Duration(milliseconds: 50));
      // Result: phone MUST NOT receive it
      expect(nativeCalls.isEmpty, isTrue,
          reason: 'Phone must NOT receive notification after Waiter A logged out');
    });

    // ============================================================
    // Test 2 — Manager isolation
    // Login as Waiter A.
    // Send a manager-only notification.
    // Result: waiter phone MUST NOT receive it.
    // ============================================================
    test('Test 2 — Manager isolation: Waiter A must NOT receive manager alerts', () async {
      final repo = ServiceRequestRepository(
        bleService,
        mockDb,
        managerPhone: '9876543210',
        currentWaiterId: 'W001',
      );

      // Send manager-only notification
      repo.triggerManagerAlert(
        title: 'Manager Alert: End of Shift Report Ready',
        body: 'Confidential supervisor report',
        requestId: 'manager_alert_01',
      );

      await Future.delayed(const Duration(milliseconds: 50));
      // Result: waiter phone MUST NOT receive it
      expect(nativeCalls.isEmpty, isTrue,
          reason: 'Waiter phone must NOT receive manager-only notification');

      repo.dispose();
    });

    // ============================================================
    // Test 3 — Waiter isolation
    // Login as Waiter A.
    // Send a notification to Waiter B.
    // Result: Waiter A\'s phone MUST NOT receive it.
    // ============================================================
    test('Test 3 — Waiter isolation: Waiter A must NOT receive Waiter B notification', () async {
      final repo = ServiceRequestRepository(
        bleService,
        mockDb,
        managerPhone: '9876543210',
        currentWaiterId: 'W001', // Waiter A
      );

      // Send alert for Table 3 assigned strictly to Waiter B (W002)
      mockDb.emitTables([
        TableModel(
          id: 'table_3',
          tableNumber: 3,
          deviceId: 'device_3',
          status: 'pending',
          flag: 0,
          assignedWaiterId: 'W002', // Waiter B
          waiterName: 'Priya Singh (W002)',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

      await Future.delayed(const Duration(milliseconds: 50));
      // Result: Waiter A's phone MUST NOT receive it
      expect(nativeCalls.isEmpty, isTrue,
          reason: 'Waiter A must NOT receive notification intended for Waiter B');

      repo.dispose();
    });

    // ============================================================
    // Test 4 — Account switching
    // Login as Waiter A.
    // Logout.
    // Login as Waiter B on the same phone.
    // Send notification to Waiter A -> Result: phone MUST NOT receive it.
    // Send notification to Waiter B -> Result: phone MUST receive it.
    // ============================================================
    test('Test 4 — Account switching on same phone reassigns device token cleanly', () async {
      const sharedDeviceToken = 'fcm_phone_token_unique_12345';

      // 1. Waiter A logs in on this phone
      await mockDb.registerDeviceFcmToken(
        token: sharedDeviceToken,
        userId: 'W001',
        role: 'waiter',
        managerPhone: '9876543210',
      );
      expect(mockDb.waiterTokensRegistry['W001']?.containsKey(
          FirebaseRealtimeService.sanitizeTokenKey(sharedDeviceToken)), isTrue);

      // 2. Waiter A logs out
      await mockDb.deactivateDeviceFcmToken(
        token: sharedDeviceToken,
        userId: 'W001',
        role: 'waiter',
        managerPhone: '9876543210',
      );
      expect(mockDb.waiterTokensRegistry['W001']?.containsKey(
          FirebaseRealtimeService.sanitizeTokenKey(sharedDeviceToken)), isFalse);

      // 3. Waiter B logs in on the SAME phone
      await mockDb.registerDeviceFcmToken(
        token: sharedDeviceToken,
        userId: 'W002',
        role: 'waiter',
        managerPhone: '9876543210',
      );
      var repoB = ServiceRequestRepository(
        bleService,
        mockDb,
        managerPhone: '9876543210',
        currentWaiterId: 'W002',
      );

      // Verify token disassociated from W001 and strictly attached to W002
      final tokenKey = FirebaseRealtimeService.sanitizeTokenKey(sharedDeviceToken);
      expect(mockDb.deviceTokensRegistry[tokenKey]?['userId'], 'W002');
      expect(mockDb.deviceTokensRegistry[tokenKey]?['active'], isTrue);
      expect(mockDb.waiterTokensRegistry['W001']?.containsKey(tokenKey) ?? false, isFalse);
      expect(mockDb.waiterTokensRegistry['W002']?.containsKey(tokenKey), isTrue);

      // 4. Send notification for Table 1 (Waiter A)
      mockDb.emitTables([
        TableModel(
          id: 'table_1',
          tableNumber: 1,
          deviceId: 'device_1',
          status: 'pending',
          flag: 0,
          assignedWaiterId: 'W001',
          waiterName: 'Rahul Sharma (W001)',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(nativeCalls.isEmpty, isTrue,
          reason: 'Phone must NOT receive Waiter A alert while Waiter B is logged in');

      // 5. Send notification for Table 3 (Waiter B)
      mockDb.emitTables([
        TableModel(
          id: 'table_3',
          tableNumber: 3,
          deviceId: 'device_3',
          status: 'pending',
          flag: 0,
          assignedWaiterId: 'W002',
          waiterName: 'Priya Singh (W002)',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(nativeCalls.length, 1,
          reason: 'Phone MUST receive Waiter B alert when logged in as Waiter B');
      expect(nativeCalls.first.arguments['tableNumber'], 3);

      repoB.dispose();
    });

    // ============================================================
    // Test 5 — Manager
    // Login as Manager.
    // Send a manager notification -> Result: manager receives it.
    // Send a waiter-only notification to Waiter A -> Result: manager does NOT receive it.
    // ============================================================
    test('Test 5 — Manager receives manager alert, but NEVER receives waiter alerts', () async {
      // Manager has empty currentWaiterId
      final managerRepo = ServiceRequestRepository(
        bleService,
        mockDb,
        managerPhone: '9876543210',
        managerUid: 'mgr_uid_001',
        currentWaiterId: '', // Manager mode
      );

      // 1. Send waiter-only notification for Table 1
      mockDb.emitTables([
        TableModel(
          id: 'table_1',
          tableNumber: 1,
          deviceId: 'device_1',
          status: 'pending',
          flag: 0,
          assignedWaiterId: 'W001',
          waiterName: 'Rahul Sharma (W001)',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);
      await Future.delayed(const Duration(milliseconds: 50));
      // Result: manager does NOT receive it
      expect(nativeCalls.isEmpty, isTrue,
          reason: 'Manager must NOT receive waiter service request notifications');

      // 2. Send manager-specific notification
      managerRepo.triggerManagerAlert(
        title: 'Manager System Alert',
        body: 'High occupancy alert across dining hall',
        requestId: 'alert_mgr_01',
      );
      await Future.delayed(const Duration(milliseconds: 50));
      // Result: manager receives it
      expect(nativeCalls.length, 1,
          reason: 'Manager MUST receive manager-specific alert');
      expect(nativeCalls.first.arguments['title'], 'Manager System Alert');

      managerRepo.dispose();
    });

    // ============================================================
    // Test 6 — Token refresh
    // Force/trigger an FCM token refresh.
    // Verify the old token is no longer treated as active.
    // Verify the new token is associated with the correct logged-in account.
    // ============================================================
    test('Test 6 — Token refresh rotates token cleanly, deactivating old and activating new', () async {
      const oldToken = 'fcm_token_initial_11111';
      const newToken = 'fcm_token_rotated_99999';
      const waiterId = 'W001';

      // 1. Register initial token
      await mockDb.registerDeviceFcmToken(
        token: oldToken,
        userId: waiterId,
        role: 'waiter',
        managerPhone: '9876543210',
      );

      final oldKey = FirebaseRealtimeService.sanitizeTokenKey(oldToken);
      final newKey = FirebaseRealtimeService.sanitizeTokenKey(newToken);

      expect(mockDb.deviceTokensRegistry[oldKey]?['active'], isTrue);
      expect(mockDb.waiterTokensRegistry[waiterId]?.containsKey(oldKey), isTrue);

      // 2. Trigger token rotation (simulate onTokenRefresh)
      await mockDb.rotateDeviceFcmToken(
        oldToken: oldToken,
        newToken: newToken,
        userId: waiterId,
        role: 'waiter',
        managerPhone: '9876543210',
      );

      // Verify old token is no longer treated as active
      expect(mockDb.deviceTokensRegistry[oldKey]?['active'], isFalse,
          reason: 'Old token must be marked inactive');
      expect(mockDb.waiterTokensRegistry[waiterId]?.containsKey(oldKey), isFalse,
          reason: 'Old token must be pruned from waiter token collection');

      // Verify new token is associated with the correct logged-in account
      expect(mockDb.deviceTokensRegistry[newKey]?['active'], isTrue,
          reason: 'New token must be active in central registry');
      expect(mockDb.deviceTokensRegistry[newKey]?['userId'], waiterId);
      expect(mockDb.deviceTokensRegistry[newKey]?['role'], 'waiter');
      expect(mockDb.waiterTokensRegistry[waiterId]?.containsKey(newKey), isTrue,
          reason: 'New token must be present in waiter token collection');
    });
  });
}
