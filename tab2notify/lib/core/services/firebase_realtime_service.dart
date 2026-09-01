import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../../features/authentication/domain/user_model.dart';
import '../../features/service_requests/domain/service_request_model.dart';
import '../../features/service_requests/domain/table_model.dart';
import '../../firebase_options.dart';

class FirebaseRealtimeService {
  static const String databaseUrl =
      'https://tab2notify-default-rtdb.asia-southeast1.firebasedatabase.app';

  late final FirebaseDatabase _db;

  FirebaseRealtimeService() {
    try {
      _db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL ?? databaseUrl,
      );
    } catch (e) {
      debugPrint('FirebaseRealtimeService instanceFor fallback: $e');
      _db = FirebaseDatabase.instance;
    }
  }

  // Users Node
  DatabaseReference get _usersRef => _db.ref('users');
  
  // Service Requests Node
  DatabaseReference get _requestsRef => _db.ref('serviceRequests');

  // Create User Profile in DB
  Future<void> createUserProfile(UserModel user) async {
    try {
      debugPrint('Writing user profile to Realtime Database: users/${user.uid}');
      await _usersRef.child(user.uid).set(user.toMap());
      debugPrint('Successfully saved user profile to Realtime Database for ${user.uid}');
    } catch (e) {
      debugPrint('Error saving user profile to Realtime Database: $e');
      rethrow;
    }
  }

  // Get User Profile
  Future<UserModel?> getUserProfile(String uid) async {
    final snapshot = await _usersRef.child(uid).get();
    if (snapshot.exists && snapshot.value != null) {
      return UserModel.fromMap(snapshot.value as Map<dynamic, dynamic>, uid);
    }
    return null;
  }

  // Listen to User Profile in real time
  Stream<UserModel?> getUserProfileStream(String uid) {
    return _usersRef.child(uid).onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return null;
      }
      final raw = snapshot.value;
      if (raw is Map) {
        return UserModel.fromMap(raw, uid);
      }
      return null;
    });
  }

  // Listen to Service Requests in real time
  Stream<List<ServiceRequestModel>> getServiceRequestsStream() {
    return _requestsRef.onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return <ServiceRequestModel>[];
      }

      final raw = snapshot.value;
      final List<ServiceRequestModel> requests = [];

      if (raw is Map) {
        raw.forEach((key, value) {
          if (value is Map) {
            requests.add(ServiceRequestModel.fromMap(value, key.toString()));
          }
        });
      } else if (raw is List) {
        for (int i = 0; i < raw.length; i++) {
          final item = raw[i];
          if (item is Map) {
            requests.add(ServiceRequestModel.fromMap(item, 'req_$i'));
          }
        }
      }

      // Sort by latest created first
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    });
  }

  // Update Request Status (Accept, Reject, Complete)
  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
    String? managerUid,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {
      'status': status,
      'updatedAt': now,
    };

    if (status == 'accepted' && managerUid != null) {
      updates['acceptedBy'] = managerUid;
      updates['acceptedAt'] = now;
    }

    await _requestsRef.child(requestId).update(updates);
  }

  // Add a new mock/ESP request
  Future<void> createRequest(ServiceRequestModel request) async {
    await _requestsRef.child(request.requestId).set(request.toMap());
  }

  // Device Status Node
  DatabaseReference get _devicesRef => _db.ref('devices');

  // Tables Node
  DatabaseReference get _tablesRef => _db.ref('tables');

  // Listen to Dynamic Tables in real time
  Stream<List<TableModel>> getTablesStream() {
    return _tablesRef.onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        seedInitialTablesIfEmpty();
        return <TableModel>[];
      }

      final raw = snapshot.value;
      final List<TableModel> tables = [];

      if (raw is Map) {
        raw.forEach((key, value) {
          if (value is Map) {
            tables.add(TableModel.fromMap(value, key.toString()));
          }
        });
      } else if (raw is List) {
        for (int i = 0; i < raw.length; i++) {
          final item = raw[i];
          if (item is Map) {
            tables.add(TableModel.fromMap(item, 'table_$i'));
          }
        }
      }

      if (tables.isEmpty) {
        seedInitialTablesIfEmpty();
      }

      // Sort by Table Number ascending
      tables.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
      return tables;
    });
  }

  // Seed default 5 tables if none exist
  Future<void> seedInitialTablesIfEmpty() async {
    final snapshot = await _tablesRef.get();
    if (!snapshot.exists || snapshot.value == null) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final Map<String, dynamic> initialTables = {};
      for (int i = 1; i <= 5; i++) {
        final tableId = 'table_$i';
        initialTables[tableId] = {
          'id': tableId,
          'table_number': i,
          'device_id': 'device_$i',
          'status': 'idle',
          'flag': -1,
          'waiter_name': '',
          'created_at': now,
          'updated_at': now,
        };
      }
      await _tablesRef.set(initialTables);
    }
  }

  // Accept a Table Request with Waiter Name (flag = 1)
  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? managerUid,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {
      'flag': 1,
      'status': 'accepted',
      'waiter_name': waiterName,
      'accepted_at': now,
      'updated_at': now,
    };
    if (managerUid != null) {
      updates['accepted_by'] = managerUid;
    }
    await _tablesRef.child(tableId).update(updates);

    // Mirror to serviceRequests node for backward compatibility
    await _requestsRef.child(tableId).update({
      'status': 'accepted',
      'acceptedBy': waiterName,
      'acceptedAt': now,
      'updatedAt': now,
    });
  }

  // Reset a Table back to Idle state (flag = -1)
  Future<void> resetTableStatus(String tableId) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {
      'flag': -1,
      'status': 'idle',
      'waiter_name': '',
      'updated_at': now,
    };
    await _tablesRef.child(tableId).update(updates);
    await _requestsRef.child(tableId).update({
      'status': 'idle',
      'updatedAt': now,
    });
  }

  // Trigger a Table Request (Customer Pressed Button, flag = 0)
  Future<void> triggerTableRequest(String tableId, {int? tableNumber}) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int tNum = tableNumber ?? (int.tryParse(tableId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1);
    final Map<String, dynamic> updates = {
      'id': tableId,
      'table_number': tNum,
      'device_id': 'device_$tNum',
      'flag': 0,
      'status': 'pending',
      'waiter_name': '',
      'updated_at': now,
      'created_at': now,
    };
    await _tablesRef.child(tableId).update(updates);
    await _requestsRef.child(tableId).set({
      'requestId': tableId,
      'roomNumber': '101',
      'tableNumber': 'T$tNum',
      'requestType': 'assistance',
      'status': 'pending',
      'priority': 'urgent',
      'createdAt': now,
    });
  }

  // Listen to ESP32 Device Status in real time
  Stream<Map<String, dynamic>?> getDeviceStatusStream(String deviceId) {
    return _devicesRef.child(deviceId).onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return null;
      }
      final Map<dynamic, dynamic> val = snapshot.value as Map<dynamic, dynamic>;
      return val.map((k, v) => MapEntry(k.toString(), v));
    });
  }

  // Update Device Heartbeat / Status
  Future<void> updateDeviceHeartbeat(String deviceId, Map<String, dynamic> data) async {
    await _devicesRef.child(deviceId).update(data);
  }
}

