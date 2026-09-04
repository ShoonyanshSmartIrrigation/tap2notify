import 'package:firebase_auth/firebase_auth.dart';
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

  String get _currentAuthUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String? get _currentAuthEmail => FirebaseAuth.instance.currentUser?.email;
  String? get _currentAuthPhone => FirebaseAuth.instance.currentUser?.phoneNumber;

  static String sanitizePhone(String phone) {
    // Keep only numeric digits
    final digits = phone.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 10) {
      // In case a country code prefix exists (e.g. 919876543210), extract the 10-digit mobile number
      return digits.substring(digits.length - 10);
    }
    return digits.isNotEmpty ? digits : 'default_manager';
  }

  String _resolvePhone(String? managerPhone) {
    if (managerPhone != null && managerPhone.trim().isNotEmpty) {
      return sanitizePhone(managerPhone);
    }
    final authPhone = _currentAuthPhone;
    if (authPhone != null && authPhone.trim().isNotEmpty) {
      return sanitizePhone(authPhone);
    }
    final authUid = _currentAuthUid;
    if (authUid.isNotEmpty) return authUid;
    return 'default_manager';
  }

  // Users Node (Root)
  DatabaseReference get _usersRef => _db.ref('users');
  
  // Manager-Scoped Waiters Node: /waiters/$managerPhone
  DatabaseReference _waitersRef(String? managerPhone) =>
      _db.ref('waiters/${_resolvePhone(managerPhone)}');

  // Manager-Scoped Tables Node: /tables/$managerPhone
  DatabaseReference _tablesRef(String? managerPhone) =>
      _db.ref('tables/${_resolvePhone(managerPhone)}');

  // Manager-Scoped Service Requests Node: /serviceRequests/$managerPhone
  DatabaseReference _requestsRef(String? managerPhone) =>
      _db.ref('serviceRequests/${_resolvePhone(managerPhone)}');

  // Hardware Device Status Node (Global device telemetry)
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
  // WAITER MANAGEMENT METHODS (Manager-Scoped by Phone)
  // -------------------------------------------------------------

  Stream<List<WaiterModel>> getWaitersStream({
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    final resolvedPhone = _resolvePhone(managerPhone);
    final ref = _waitersRef(resolvedPhone);

    return ref.onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        seedInitialWaitersIfEmpty(
          managerPhone: resolvedPhone,
          managerUid: managerUid,
          managerEmail: managerEmail,
        );
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
        seedInitialWaitersIfEmpty(
          managerPhone: resolvedPhone,
          managerUid: managerUid,
          managerEmail: managerEmail,
        );
      }

      waiters.sort((a, b) => a.waiterId.compareTo(b.waiterId));
      return waiters;
    });
  }

  Future<List<WaiterModel>> fetchWaitersByPhone(String managerPhone) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final snapshot = await _waitersRef(resolvedPhone).get();
    if (!snapshot.exists || snapshot.value == null) {
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

    waiters.sort((a, b) => a.waiterId.compareTo(b.waiterId));
    return waiters;
  }

  Future<void> saveWaiter(
    WaiterModel waiter, {
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) async {
    final resolvedPhone = waiter.managerPhone.isNotEmpty
        ? sanitizePhone(waiter.managerPhone)
        : _resolvePhone(managerPhone);
    final resolvedUid = waiter.managerUid.isNotEmpty ? waiter.managerUid : _currentAuthUid;
    final resolvedEmail = waiter.managerEmail ?? managerEmail ?? _currentAuthEmail;

    final updatedWaiter = waiter.copyWith(
      managerPhone: resolvedPhone,
      managerUid: resolvedUid,
      managerEmail: resolvedEmail,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _waitersRef(resolvedPhone)
        .child(updatedWaiter.waiterId)
        .set(updatedWaiter.toMap());
  }

  Future<void> deleteWaiter(
    String waiterId, {
    String? managerPhone,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    await _waitersRef(resolvedPhone).child(waiterId).remove();

    // Also remove waiter assignment from all tables belonging to this manager
    final snapshot = await _tablesRef(resolvedPhone).get();
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
        await _tablesRef(resolvedPhone).update(updates);
      }
    }
  }

  Future<void> seedInitialWaitersIfEmpty({
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final resolvedUid = managerUid ?? _currentAuthUid;
    final resolvedEmail = managerEmail ?? _currentAuthEmail;
    final ref = _waitersRef(resolvedPhone);

    final snapshot = await ref.get();
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
          'managerPhone': resolvedPhone,
          'manager_phone': resolvedPhone,
          'managerUid': resolvedUid,
          'managerEmail': resolvedEmail,
          'createdAt': now,
          'updatedAt': now,
        },
        'W002': {
          'waiterId': 'W002',
          'name': 'Priya Singh',
          'phone': '+91 98765 00002',
          'passcode': '1234',
          'status': 'active',
          'assignedTableIds': ['table_3', 'table_4'],
          'managerPhone': resolvedPhone,
          'manager_phone': resolvedPhone,
          'managerUid': resolvedUid,
          'managerEmail': resolvedEmail,
          'createdAt': now,
          'updatedAt': now,
        },
        'W003': {
          'waiterId': 'W003',
          'name': 'Amit Patel',
          'phone': '+91 98765 00003',
          'passcode': '1234',
          'status': 'active',
          'assignedTableIds': ['table_5'],
          'managerPhone': resolvedPhone,
          'manager_phone': resolvedPhone,
          'managerUid': resolvedUid,
          'managerEmail': resolvedEmail,
          'createdAt': now,
          'updatedAt': now,
        },
      };
      await ref.set(initialWaiters);
    }
  }

  // -------------------------------------------------------------
  // TABLE CONFIGURATION & ASSIGNMENT METHODS (Manager-Scoped by Phone)
  // -------------------------------------------------------------

  // Batch configure / generate N tables for a manager (e.g. 20 tables)
  Future<void> batchConfigureTables(
    int totalCount, {
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final resolvedUid = managerUid ?? _currentAuthUid;
    final resolvedEmail = managerEmail ?? _currentAuthEmail;
    final ref = _tablesRef(resolvedPhone);

    final snapshot = await ref.get();
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
          'manager_phone': resolvedPhone,
          'manager_uid': resolvedUid,
          'manager_email': resolvedEmail,
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
          'manager_phone': resolvedPhone,
          'manager_uid': resolvedUid,
          'manager_email': resolvedEmail,
          'created_at': now,
          'updated_at': now,
        };
      }
    }

    await ref.set(updatedTables);
  }

  // Assign Waiter to one or multiple tables (scoped to manager's phone)
  Future<void> assignWaiterToTables({
    required String waiterId,
    required String waiterName,
    required List<String> tableIds,
    String? managerPhone,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {};

    for (final tableId in tableIds) {
      updates['$tableId/assigned_waiter_id'] = waiterId;
      updates['$tableId/assigned_waiter_name'] = waiterName;
      updates['$tableId/waiter_name'] = waiterName;
      updates['$tableId/updated_at'] = now;
    }

    if (updates.isNotEmpty) {
      await _tablesRef(resolvedPhone).update(updates);
    }

    // Synchronize all waiters' assignedTableIds in /waiters/$managerPhone
    final allWaitersSnap = await _waitersRef(resolvedPhone).get();
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
        await _waitersRef(resolvedPhone).update(waiterUpdates);
      }
    }
  }

  // Remove Waiter Assignment from a Table
  Future<void> removeWaiterFromTable(
    String tableId, {
    String? managerPhone,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final int now = DateTime.now().millisecondsSinceEpoch;

    await _tablesRef(resolvedPhone).child(tableId).update({
      'assigned_waiter_id': '',
      'assigned_waiter_name': '',
      'waiter_name': '',
      'updated_at': now,
    });

    // Remove tableId from all waiters in /waiters/$managerPhone
    final allWaitersSnap = await _waitersRef(resolvedPhone).get();
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
        await _waitersRef(resolvedPhone).update(waiterUpdates);
      }
    }
  }

  // Listen to ALL Tables for a specific Manager in real time (scoped by Phone)
  Stream<List<TableModel>> getTablesStream({
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    final resolvedPhone = _resolvePhone(managerPhone);
    final ref = _tablesRef(resolvedPhone);

    return ref.onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        seedInitialTablesIfEmpty(
          managerPhone: resolvedPhone,
          managerUid: managerUid,
          managerEmail: managerEmail,
        );
        return <TableModel>[];
      }

      final raw = snapshot.value;
      final List<TableModel> tables = [];

      if (raw is Map) {
        final List<String> invalidKeys = [];
        raw.forEach((key, value) {
          if (value is Map) {
            final table = TableModel.fromMap(value, key.toString());
            // Only accept valid configured floor tables (1 to 100)
            if (table.tableNumber >= 1 && table.tableNumber <= 100) {
              tables.add(table);
            } else {
              invalidKeys.add(key.toString());
            }
          }
        });
        // Auto purge rogue/phantom keys from manager's node
        if (invalidKeys.isNotEmpty) {
          for (final rogueKey in invalidKeys) {
            ref.child(rogueKey).remove();
          }
        }
      } else if (raw is List) {
        for (int i = 0; i < raw.length; i++) {
          final item = raw[i];
          if (item is Map) {
            final table = TableModel.fromMap(item, 'table_$i');
            if (table.tableNumber >= 1 && table.tableNumber <= 100) {
              tables.add(table);
            }
          }
        }
      }

      if (tables.isEmpty) {
        seedInitialTablesIfEmpty(
          managerPhone: resolvedPhone,
          managerUid: managerUid,
          managerEmail: managerEmail,
        );
      }

      tables.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
      return tables;
    });
  }

  // Listen to STRICTLY Assigned Tables in real time for a Waiter under a Manager Phone
  Stream<List<TableModel>> getTablesForWaiterStream(
    String waiterId, {
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    return getTablesStream(
      managerPhone: managerPhone,
      managerUid: managerUid,
      managerEmail: managerEmail,
    ).map((allTables) {
      return allTables
          .where((t) => t.assignedWaiterId == waiterId || t.waiterName == waiterId)
          .toList();
    });
  }

  // Seed default 5 tables if none exist for this manager
  Future<void> seedInitialTablesIfEmpty({
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final resolvedUid = managerUid ?? _currentAuthUid;
    final resolvedEmail = managerEmail ?? _currentAuthEmail;
    final ref = _tablesRef(resolvedPhone);

    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.value == null) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final Map<String, dynamic> initialTables = {};
      final initialWaiters = [
        'Rahul Sharma (W001)',
        'Rahul Sharma (W001)',
        'Priya Singh (W002)',
        'Priya Singh (W002)',
        'Amit Patel (W003)'
      ];
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
          'manager_phone': resolvedPhone,
          'manager_uid': resolvedUid,
          'manager_email': resolvedEmail,
          'created_at': now,
          'updated_at': now,
        };
      }
      await ref.set(initialTables);
    }
  }

  // -------------------------------------------------------------
  // SERVICE REQUEST METHODS (Manager-Scoped by Phone)
  // -------------------------------------------------------------

  // Accept a Table Request with Waiter Name (flag = 1)
  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? waiterId,
    String? managerPhone,
    String? managerUid,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> tableUpdates = {
      'flag': 1,
      'status': 'accepted',
      'waiter_name': waiterName,
      'accepted_at': now,
      'updated_at': now,
    };
    if (waiterId != null && waiterId.isNotEmpty) {
      tableUpdates['assigned_waiter_id'] = waiterId;
      tableUpdates['assigned_waiter_name'] = waiterName;
    }
    if (managerUid != null && managerUid.isNotEmpty) {
      tableUpdates['accepted_by'] = managerUid;
    }
    await _tablesRef(resolvedPhone).child(tableId).update(tableUpdates);

    await _requestsRef(resolvedPhone).child(tableId).update({
      'status': 'accepted',
      'acceptedBy': waiterName,
      'assignedWaiterId': waiterId ?? '',
      'acceptedAt': now,
      'updatedAt': now,
    });
  }

  // Complete / Reset a Table back to Idle state (flag = -1)
  Future<void> resetTableStatus(
    String tableId, {
    String? managerPhone,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {
      'flag': -1,
      'status': 'idle',
      'updated_at': now,
    };
    await _tablesRef(resolvedPhone).child(tableId).update(updates);
    await _requestsRef(resolvedPhone).child(tableId).update({
      'status': 'idle',
      'updatedAt': now,
    });
  }

  // Trigger a Table Request (Customer / ESP32 Pressed Button, flag = 0)
  Future<void> triggerTableRequest(
    String tableId, {
    int? tableNumber,
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final resolvedUid = managerUid ?? _currentAuthUid;
    final resolvedEmail = managerEmail ?? _currentAuthEmail;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int tNum = tableNumber ?? (int.tryParse(tableId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1);
    
    // Get existing table assignment
    final snapshot = await _tablesRef(resolvedPhone).child(tableId).get();
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
      'manager_phone': resolvedPhone,
      'manager_uid': resolvedUid,
      'manager_email': resolvedEmail,
      'updated_at': now,
      'created_at': now,
    };
    await _tablesRef(resolvedPhone).child(tableId).update(updates);
    await _requestsRef(resolvedPhone).child(tableId).set({
      'requestId': tableId,
      'roomNumber': '101',
      'tableNumber': 'T$tNum',
      'assignedWaiterId': wId,
      'assignedWaiterName': wName,
      'requestType': 'assistance',
      'status': 'pending',
      'priority': 'urgent',
      'managerPhone': resolvedPhone,
      'manager_phone': resolvedPhone,
      'managerUid': resolvedUid,
      'managerEmail': resolvedEmail,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  // Listen to Service Requests in real time (scoped by Phone)
  Stream<List<ServiceRequestModel>> getServiceRequestsStream({
    String? managerPhone,
  }) {
    final resolvedPhone = _resolvePhone(managerPhone);
    return _requestsRef(resolvedPhone).onValue.map((event) {
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
    String? managerPhone,
    String? managerUid,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {
      'status': status,
      'updatedAt': now,
    };

    if (status == 'accepted' && managerUid != null && managerUid.isNotEmpty) {
      updates['acceptedBy'] = managerUid;
      updates['acceptedAt'] = now;
    }

    await _requestsRef(resolvedPhone).child(requestId).update(updates);
  }

  Future<void> createRequest(
    ServiceRequestModel request, {
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) async {
    final resolvedPhone = request.managerPhone.isNotEmpty
        ? sanitizePhone(request.managerPhone)
        : _resolvePhone(managerPhone);
    final resolvedUid = request.managerUid.isNotEmpty
        ? request.managerUid
        : _currentAuthUid;
    final resolvedEmail = request.managerEmail ?? managerEmail ?? _currentAuthEmail;

    final updated = request.copyWith(
      managerPhone: resolvedPhone,
      managerUid: resolvedUid,
      managerEmail: resolvedEmail,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _requestsRef(resolvedPhone).child(updated.requestId).set(updated.toMap());
  }

  // Sync live BLE table status and online presence to Firebase (ONLY for existing configured tables of manager)
  Future<void> syncBleDeviceStatus({
    required String tableId,
    required int tableNumber,
    required String status,
    required int flag,
    required bool isOnline,
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final resolvedUid = managerUid ?? _currentAuthUid;
    final resolvedEmail = managerEmail ?? _currentAuthEmail;
    final tableSnap = await _tablesRef(resolvedPhone).child(tableId).get();
    if (!tableSnap.exists) {
      // Table is not part of this manager's configured tables; ignore to prevent phantom tables
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {
      'device_online': isOnline,
      'status': status,
      'flag': flag,
      'manager_phone': resolvedPhone,
      'manager_uid': resolvedUid,
      'manager_email': resolvedEmail,
      'updated_at': now,
    };
    await _tablesRef(resolvedPhone).child(tableId).update(updates);
    if (flag == 0) {
      // Ensure urgent request exists in /serviceRequests/$managerPhone
      await _requestsRef(resolvedPhone).child(tableId).set({
        'requestId': tableId,
        'roomNumber': '101',
        'tableNumber': 'T$tableNumber',
        'requestType': 'assistance',
        'status': 'pending',
        'priority': 'urgent',
        'managerPhone': resolvedPhone,
        'manager_phone': resolvedPhone,
        'managerUid': resolvedUid,
        'managerEmail': resolvedEmail,
        'createdAt': now,
        'updatedAt': now,
      });
    }
  }

  Future<void> updateDeviceOnlineStatus(
    String tableId,
    bool isOnline, {
    String? managerPhone,
  }) async {
    final resolvedPhone = _resolvePhone(managerPhone);
    final tableSnap = await _tablesRef(resolvedPhone).child(tableId).get();
    if (!tableSnap.exists) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    await _tablesRef(resolvedPhone).child(tableId).update({
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


