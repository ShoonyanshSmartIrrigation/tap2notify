import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../../features/authentication/domain/user_model.dart';
import '../../features/service_requests/domain/service_request_model.dart';
import '../../features/service_requests/domain/table_model.dart';
import '../../features/waiter/domain/waiter_model.dart';
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
  
  // Waiters Node
  DatabaseReference get _waitersRef => _db.ref('waiters');

  // Tables Node
  DatabaseReference get _tablesRef => _db.ref('tables');

  // Service Requests Node
  DatabaseReference get _requestsRef => _db.ref('serviceRequests');

  // Device Status Node
  DatabaseReference get _devicesRef => _db.ref('devices');

  // -------------------------------------------------------------
  // USER PROFILE METHODS
  // -------------------------------------------------------------

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

  Future<UserModel?> getUserProfile(String uid) async {
    final snapshot = await _usersRef.child(uid).get();
    if (snapshot.exists && snapshot.value != null) {
      return UserModel.fromMap(snapshot.value as Map<dynamic, dynamic>, uid);
    }
    return null;
  }

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

  // -------------------------------------------------------------
  // WAITER MANAGEMENT METHODS
  // -------------------------------------------------------------

  Stream<List<WaiterModel>> getWaitersStream() {
    return _waitersRef.onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        seedInitialWaitersIfEmpty();
        return <WaiterModel>[];
      }

      final raw = snapshot.value;
      final List<WaiterModel> waiters = [];

      if (raw is Map) {
        raw.forEach((key, value) {
          if (value is Map) {
            waiters.add(WaiterModel.fromMap(value, key.toString()));
          }
        });
      }

      if (waiters.isEmpty) {
        seedInitialWaitersIfEmpty();
      }

      waiters.sort((a, b) => a.waiterId.compareTo(b.waiterId));
      return waiters;
    });
  }

  Future<void> saveWaiter(WaiterModel waiter) async {
    await _waitersRef.child(waiter.waiterId).set(waiter.toMap());
  }

  Future<void> deleteWaiter(String waiterId) async {
    await _waitersRef.child(waiterId).remove();
    // Also remove waiter assignment from all tables assigned to this waiter
    final snapshot = await _tablesRef.get();
    if (snapshot.exists && snapshot.value is Map) {
      final tablesMap = snapshot.value as Map;
      final Map<String, dynamic> updates = {};
      tablesMap.forEach((key, value) {
        if (value is Map &&
            (value['assigned_waiter_id'] == waiterId || value['waiter_name'] == waiterId)) {
          updates['$key/assigned_waiter_id'] = '';
          updates['$key/assigned_waiter_name'] = '';
          updates['$key/waiter_name'] = '';
        }
      });
      if (updates.isNotEmpty) {
        await _tablesRef.update(updates);
      }
    }
  }

  Future<void> seedInitialWaitersIfEmpty() async {
    final snapshot = await _waitersRef.get();
    if (!snapshot.exists || snapshot.value == null) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final Map<String, dynamic> initialWaiters = {
        'W001': {
          'waiterId': 'W001',
          'name': 'Rahul Sharma',
          'phone': '+91 98765 00001',
          'passcode': '1234',
          'status': 'active',
          'assignedTableIds': ['table_1', 'table_2'],
          'createdAt': now,
        },
        'W002': {
          'waiterId': 'W002',
          'name': 'Priya Singh',
          'phone': '+91 98765 00002',
          'passcode': '1234',
          'status': 'active',
          'assignedTableIds': ['table_3', 'table_4'],
          'createdAt': now,
        },
        'W003': {
          'waiterId': 'W003',
          'name': 'Amit Patel',
          'phone': '+91 98765 00003',
          'passcode': '1234',
          'status': 'active',
          'assignedTableIds': ['table_5'],
          'createdAt': now,
        },
      };
      await _waitersRef.set(initialWaiters);
    }
  }

  // -------------------------------------------------------------
  // TABLE CONFIGURATION & ASSIGNMENT METHODS
  // -------------------------------------------------------------

  // Batch configure / generate N tables (e.g. 20 tables)
  Future<void> batchConfigureTables(int totalCount) async {
    final snapshot = await _tablesRef.get();
    final Map<dynamic, dynamic> existingTables =
        (snapshot.exists && snapshot.value is Map) ? snapshot.value as Map : {};

    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updatedTables = {};

    for (int i = 1; i <= totalCount; i++) {
      final tableId = 'table_$i';
      if (existingTables.containsKey(tableId) && existingTables[tableId] is Map) {
        // Preserve existing table data and assignment
        final existing = existingTables[tableId] as Map;
        updatedTables[tableId] = {
          'id': tableId,
          'table_number': i,
          'device_id': existing['device_id'] ?? 'device_$i',
          'status': existing['status'] ?? 'idle',
          'flag': existing['flag'] ?? -1,
          'waiter_name': existing['waiter_name'] ?? existing['assigned_waiter_name'] ?? '',
          'assigned_waiter_id': existing['assigned_waiter_id'] ?? '',
          'assigned_waiter_name': existing['assigned_waiter_name'] ?? existing['waiter_name'] ?? '',
          'created_at': existing['created_at'] ?? now,
          'updated_at': now,
        };
      } else {
        // Create new table
        updatedTables[tableId] = {
          'id': tableId,
          'table_number': i,
          'device_id': 'device_$i',
          'status': 'idle',
          'flag': -1,
          'waiter_name': '',
          'assigned_waiter_id': '',
          'assigned_waiter_name': '',
          'created_at': now,
          'updated_at': now,
        };
      }
    }

    await _tablesRef.set(updatedTables);
  }

  // Assign Waiter to one or multiple tables
  Future<void> assignWaiterToTables({
    required String waiterId,
    required String waiterName,
    required List<String> tableIds,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {};

    for (final tableId in tableIds) {
      updates['$tableId/assigned_waiter_id'] = waiterId;
      updates['$tableId/assigned_waiter_name'] = waiterName;
      updates['$tableId/waiter_name'] = waiterName;
      updates['$tableId/updated_at'] = now;
    }

    if (updates.isNotEmpty) {
      await _tablesRef.update(updates);
    }

    // Synchronize all waiters' assignedTableIds in /waiters
    final allWaitersSnap = await _waitersRef.get();
    if (allWaitersSnap.exists && allWaitersSnap.value is Map) {
      final allWaiters = allWaitersSnap.value as Map;
      final Map<String, dynamic> waiterUpdates = {};

      allWaiters.forEach((wKey, wVal) {
        if (wVal is Map) {
          final String currentWId = wKey.toString();
          List<String> currentTables = [];
          if (wVal['assignedTableIds'] is List) {
            currentTables = (wVal['assignedTableIds'] as List)
                .map((e) => e.toString())
                .where((t) => !tableIds.contains(t))
                .toList();
          }

          if (currentWId == waiterId) {
            for (final tId in tableIds) {
              if (!currentTables.contains(tId)) {
                currentTables.add(tId);
              }
            }
          }

          waiterUpdates['$currentWId/assignedTableIds'] = currentTables;
          waiterUpdates['$currentWId/updatedAt'] = now;
        }
      });

      if (waiterUpdates.isNotEmpty) {
        await _waitersRef.update(waiterUpdates);
      }
    }
  }

  // Remove Waiter Assignment from a Table
  Future<void> removeWaiterFromTable(String tableId) async {
    final int now = DateTime.now().millisecondsSinceEpoch;

    await _tablesRef.child(tableId).update({
      'assigned_waiter_id': '',
      'assigned_waiter_name': '',
      'waiter_name': '',
      'updated_at': now,
    });

    // Remove tableId from all waiters in /waiters
    final allWaitersSnap = await _waitersRef.get();
    if (allWaitersSnap.exists && allWaitersSnap.value is Map) {
      final allWaiters = allWaitersSnap.value as Map;
      final Map<String, dynamic> waiterUpdates = {};

      allWaiters.forEach((wKey, wVal) {
        if (wVal is Map && wVal['assignedTableIds'] is List) {
          final current = (wVal['assignedTableIds'] as List)
              .map((e) => e.toString())
              .where((id) => id != tableId)
              .toList();
          waiterUpdates['$wKey/assignedTableIds'] = current;
          waiterUpdates['$wKey/updatedAt'] = now;
        }
      });

      if (waiterUpdates.isNotEmpty) {
        await _waitersRef.update(waiterUpdates);
      }
    }
  }

  // Listen to ALL Tables in real time (for Manager)
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

      tables.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
      return tables;
    });
  }

  // Listen to STRICTLY Assigned Tables in real time (for Waiter)
  Stream<List<TableModel>> getTablesForWaiterStream(String waiterId) {
    return getTablesStream().map((allTables) {
      return allTables
          .where((t) => t.assignedWaiterId == waiterId || t.waiterName == waiterId)
          .toList();
    });
  }

  // Seed default 5 tables if none exist
  Future<void> seedInitialTablesIfEmpty() async {
    final snapshot = await _tablesRef.get();
    if (!snapshot.exists || snapshot.value == null) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final Map<String, dynamic> initialTables = {};
      final initialWaiters = ['Rahul Sharma (W001)', 'Rahul Sharma (W001)', 'Priya Singh (W002)', 'Priya Singh (W002)', 'Amit Patel (W003)'];
      final initialWaiterIds = ['W001', 'W001', 'W002', 'W002', 'W003'];

      for (int i = 1; i <= 5; i++) {
        final tableId = 'table_$i';
        initialTables[tableId] = {
          'id': tableId,
          'table_number': i,
          'device_id': 'device_$i',
          'status': 'idle',
          'flag': -1,
          'waiter_name': initialWaiters[i - 1],
          'assigned_waiter_id': initialWaiterIds[i - 1],
          'assigned_waiter_name': initialWaiters[i - 1],
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
    String? waiterId,
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
    if (waiterId != null && waiterId.isNotEmpty) {
      updates['assigned_waiter_id'] = waiterId;
      updates['assigned_waiter_name'] = waiterName;
    }
    if (managerUid != null) {
      updates['accepted_by'] = managerUid;
    }
    await _tablesRef.child(tableId).update(updates);

    await _requestsRef.child(tableId).update({
      'status': 'accepted',
      'acceptedBy': waiterName,
      'assignedWaiterId': waiterId ?? '',
      'acceptedAt': now,
      'updatedAt': now,
    });
  }

  // Complete / Reset a Table back to Idle state (flag = -1)
  Future<void> resetTableStatus(String tableId) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {
      'flag': -1,
      'status': 'idle',
      'updated_at': now,
    };
    await _tablesRef.child(tableId).update(updates);
    await _requestsRef.child(tableId).update({
      'status': 'idle',
      'updatedAt': now,
    });
  }

  // Trigger a Table Request (Customer / ESP32 Pressed Button, flag = 0)
  Future<void> triggerTableRequest(String tableId, {int? tableNumber}) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int tNum = tableNumber ?? (int.tryParse(tableId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1);
    
    // Get existing table assignment
    final snapshot = await _tablesRef.child(tableId).get();
    String wName = '';
    String wId = '';
    if (snapshot.exists && snapshot.value is Map) {
      final map = snapshot.value as Map;
      wName = map['assigned_waiter_name']?.toString() ?? map['waiter_name']?.toString() ?? '';
      wId = map['assigned_waiter_id']?.toString() ?? '';
    }

    final Map<String, dynamic> updates = {
      'id': tableId,
      'table_number': tNum,
      'device_id': 'device_$tNum',
      'flag': 0,
      'status': 'pending',
      'updated_at': now,
      'created_at': now,
    };
    await _tablesRef.child(tableId).update(updates);
    await _requestsRef.child(tableId).set({
      'requestId': tableId,
      'roomNumber': '101',
      'tableNumber': 'T$tNum',
      'assignedWaiterId': wId,
      'assignedWaiterName': wName,
      'requestType': 'assistance',
      'status': 'pending',
      'priority': 'urgent',
      'createdAt': now,
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

      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    });
  }

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

  Future<void> createRequest(ServiceRequestModel request) async {
    await _requestsRef.child(request.requestId).set(request.toMap());
  }

  // Sync live BLE table status and online presence to Firebase
  Future<void> syncBleDeviceStatus({
    required String tableId,
    required int tableNumber,
    required String status,
    required int flag,
    required bool isOnline,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {
      'id': tableId,
      'table_number': tableNumber,
      'device_id': 'device_$tableNumber',
      'device_online': isOnline,
      'status': status,
      'flag': flag,
      'updated_at': now,
    };
    await _tablesRef.child(tableId).update(updates);
    if (flag == 0) {
      // Ensure urgent request exists in /requests
      await _requestsRef.child(tableId).set({
        'requestId': tableId,
        'roomNumber': '101',
        'tableNumber': 'T$tableNumber',
        'requestType': 'assistance',
        'status': 'pending',
        'priority': 'urgent',
        'createdAt': now,
      });
    }
  }

  Future<void> updateDeviceOnlineStatus(String tableId, bool isOnline) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    await _tablesRef.child(tableId).update({
      'device_online': isOnline,
      'updated_at': now,
    });
  }

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

  Future<void> updateDeviceHeartbeat(String deviceId, Map<String, dynamic> data) async {
    await _devicesRef.child(deviceId).update(data);
  }
}


