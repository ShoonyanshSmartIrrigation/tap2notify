import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/services/ble_service.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/firebase_realtime_service.dart';
import '../../waiter/domain/waiter_model.dart';
import '../domain/table_model.dart';

class ServiceRequestRepository {
  final BleService _bleService;
  final FirebaseRealtimeService _dbService;
  final String managerPhone;
  final String managerUid;
  final String? managerEmail;
  final String currentWaiterId;

  final Map<String, int> _lastNotifiedTime = {};
  StreamSubscription<List<TableModel>>? _cloudRequestSub;

  ServiceRequestRepository(
    this._bleService,
    this._dbService, {
    this.managerPhone = '',
    this.managerUid = '',
    this.managerEmail,
    this.currentWaiterId = '',
  }) {
    // Forward BLE physical device discoveries to Firebase Realtime Database asynchronously
    _bleService.onDeviceDiscovered = (TableModel bleTable) {
      debugPrint('[BLE DISCOVERED HOOK] Table ${bleTable.tableNumber} (${bleTable.id}) status=${bleTable.status} flag=${bleTable.flag} managerPhone=$managerPhone currentWaiterId=$currentWaiterId');
      // Instant Native Notification Alert for urgent service requests
      if (bleTable.flag == 0) {
        _triggerRequestNotification(
          tableId: bleTable.id,
          tableNumber: bleTable.tableNumber,
          assignedWaiterId: bleTable.assignedWaiterId,
          waiterName: bleTable.waiterName,
        );
      }

      if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
        _dbService.syncBleDeviceStatus(
          tableId: bleTable.id,
          tableNumber: bleTable.tableNumber,
          status: bleTable.status,
          flag: bleTable.flag,
          isOnline: true,
          managerPhone: managerPhone,
          managerUid: managerUid,
          managerEmail: managerEmail,
        ).catchError((err) {
          debugPrint('[SYNC ERROR] Failed to sync BLE device to cloud: $err');
        });
      }
    };

    _bleService.onDeviceLost = (String tableId) {
      if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
        _dbService.updateDeviceOnlineStatus(
          tableId,
          false,
          managerPhone: managerPhone,
        ).catchError((err) {
          debugPrint('[SYNC ERROR] Failed to update offline status: $err');
        });
      }
    };

    // Listen to RTDB tables to alert if status is set to pending from cloud/web
    if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
      _startCloudRequestListener();
    }
  }

  void _startCloudRequestListener() {
    _cloudRequestSub?.cancel();
    _cloudRequestSub = _dbService
        .getTablesStream(
          managerPhone: managerPhone,
          managerUid: managerUid,
          managerEmail: managerEmail,
        )
        .listen((tables) {
      for (final table in tables) {
        if (table.flag == 0 || table.status == 'pending') {
          _triggerRequestNotification(
            tableId: table.id,
            tableNumber: table.tableNumber,
            assignedWaiterId: table.assignedWaiterId,
            waiterName: table.waiterName,
          );
        }
      }
    }, onError: (e) {
      debugPrint('[CLOUD NOTIF LISTENER] Error: $e');
    });
  }

  void _triggerRequestNotification({
    required String tableId,
    required int tableNumber,
    String assignedWaiterId = '',
    String waiterName = '',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastNotifiedTime[tableId] ?? 0;
    // Debounce duplicate alerts within 6 seconds
    if (now - last < 6000) return;

    // 1. If user is a MANAGER: Table service requests are intended for Waiters, NOT the Manager.
    // Suppress waiter table alerts on the manager's device.
    if (currentWaiterId.isEmpty) {
      debugPrint('[NOTIF SCOPE] Table $tableNumber service request suppressed for Manager (waiter-only alert).');
      return;
    }

    // 2. If user is a WAITER: Strictly verify the table is assigned to THIS waiter.
    final isAssigned = (assignedWaiterId.isNotEmpty && assignedWaiterId == currentWaiterId) ||
        waiterName.contains('($currentWaiterId)') ||
        (waiterName.isNotEmpty && waiterName == currentWaiterId);

    if (!isAssigned) {
      debugPrint('[NOTIF SCOPE] Table $tableNumber not assigned to Waiter $currentWaiterId. Alert suppressed.');
      return;
    }

    _lastNotifiedTime[tableId] = now;
    debugPrint('[NOTIFICATION TRIGGER] Showing OS notification for Table $tableNumber ($tableId) to Waiter $currentWaiterId');
    FCMService().showNativeNotification(
      title: '🛎️ Table $tableNumber Calling!',
      body: 'Customer requested immediate assistance at Table $tableNumber 🔴',
      requestId: tableId,
      tableNumber: tableNumber,
    );
  }

  /// Triggers a manager-specific notification (e.g. system alerts, staff call, supervisor escalation)
  void triggerManagerAlert({
    required String title,
    required String body,
    required String requestId,
  }) {
    // Waiters must NEVER receive manager alerts
    if (currentWaiterId.isNotEmpty) {
      debugPrint('[NOTIF SCOPE] Manager alert suppressed on Waiter device ($currentWaiterId)');
      return;
    }

    debugPrint('[MANAGER ALERT TRIGGER] Showing manager alert: $title');
    FCMService().showNativeNotification(
      title: title,
      body: body,
      requestId: requestId,
    );
  }

  // Stream all tables for the manager with live merged BLE online status
  Stream<List<TableModel>> getTablesStream() {
    late StreamController<List<TableModel>> controller;
    StreamSubscription? dbSub;
    StreamSubscription? bleSub;
    List<TableModel> lastDbTables = [];

    List<TableModel> computeMerged() {
      if (lastDbTables.isEmpty) {
        return _bleService.currentTables;
      }
      final merged = lastDbTables.map((t) {
        final isBleOnline = _bleService.isTableOnline(t.id);
        final liveBleTable = _bleService.getLiveBleTable(t.id);
        if (liveBleTable != null) {
          return t.copyWith(
            isDeviceOnline: isBleOnline,
            status: liveBleTable.status,
            flag: liveBleTable.flag,
            waiterName: liveBleTable.waiterName.isNotEmpty ? liveBleTable.waiterName : t.waiterName,
          );
        }
        return t.copyWith(isDeviceOnline: isBleOnline);
      }).toList();

      for (final bleTable in _bleService.currentTables) {
        if (!merged.any((m) => m.id == bleTable.id || m.tableNumber == bleTable.tableNumber)) {
          merged.add(bleTable);
        }
      }
      merged.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
      return merged;
    }

    controller = StreamController<List<TableModel>>(
      onListen: () {
        dbSub = _dbService.getTablesStream(
          managerPhone: managerPhone,
          managerUid: managerUid,
          managerEmail: managerEmail,
        ).listen(
          (dbList) {
            lastDbTables = dbList;
            scheduleMicrotask(() {
              if (!controller.isClosed) {
                controller.add(computeMerged());
              }
            });
          },
          onError: (e) {
            scheduleMicrotask(() {
              if (!controller.isClosed) controller.addError(e);
            });
          },
        );

        bleSub = _bleService.tablesStream.listen(
          (_) {
            scheduleMicrotask(() {
              if (!controller.isClosed) {
                controller.add(computeMerged());
              }
            });
          },
        );
      },
      onCancel: () {
        dbSub?.cancel();
        bleSub?.cancel();
      },
    );

    return controller.stream;
  }

  // Stream only tables assigned to a specific waiter with live merged BLE online status
  Stream<List<TableModel>> getTablesForWaiterStream(String waiterId) {
    late StreamController<List<TableModel>> controller;
    StreamSubscription? dbSub;
    StreamSubscription? bleSub;
    List<TableModel> lastDbTables = [];

    List<TableModel> computeMerged() {
      if (lastDbTables.isEmpty) {
        return _bleService.currentTables.where((t) {
          return (t.assignedWaiterId.isNotEmpty && t.assignedWaiterId == waiterId) ||
              t.waiterName.contains('($waiterId)') ||
              (t.waiterName.isNotEmpty && t.waiterName == waiterId);
        }).toList();
      }
      return lastDbTables.map((t) {
        final isBleOnline = _bleService.isTableOnline(t.id);
        final liveBleTable = _bleService.getLiveBleTable(t.id);
        if (liveBleTable != null) {
          return t.copyWith(
            isDeviceOnline: isBleOnline,
            status: liveBleTable.status,
            flag: liveBleTable.flag,
            waiterName: liveBleTable.waiterName.isNotEmpty ? liveBleTable.waiterName : t.waiterName,
          );
        }
        return t.copyWith(isDeviceOnline: isBleOnline);
      }).toList();
    }

    controller = StreamController<List<TableModel>>(
      onListen: () {
        dbSub = _dbService.getTablesForWaiterStream(
          waiterId,
          managerPhone: managerPhone,
          managerUid: managerUid,
          managerEmail: managerEmail,
        ).listen(
          (dbList) {
            lastDbTables = dbList;
            scheduleMicrotask(() {
              if (!controller.isClosed) {
                controller.add(computeMerged());
              }
            });
          },
          onError: (e) {
            scheduleMicrotask(() {
              if (!controller.isClosed) controller.addError(e);
            });
          },
        );

        bleSub = _bleService.tablesStream.listen(
          (_) {
            scheduleMicrotask(() {
              if (!controller.isClosed) {
                controller.add(computeMerged());
              }
            });
          },
        );
      },
      onCancel: () {
        dbSub?.cancel();
        bleSub?.cancel();
      },
    );

    return controller.stream;
  }

  // Stream registered waiters for this manager
  Stream<List<WaiterModel>> getWaitersStream() {
    return _dbService.getWaitersStream(
      managerPhone: managerPhone,
      managerUid: managerUid,
      managerEmail: managerEmail,
    );
  }

  // Configure total tables for this manager (e.g. 20)
  Future<void> batchConfigureTables(int count) async {
    await _dbService.batchConfigureTables(
      count,
      managerPhone: managerPhone,
      managerUid: managerUid,
      managerEmail: managerEmail,
    );
  }

  // Assign Waiter to tables for this manager
  Future<void> assignWaiterToTables({
    required String waiterId,
    required String waiterName,
    required List<String> tableIds,
  }) async {
    await _dbService.assignWaiterToTables(
      waiterId: waiterId,
      waiterName: waiterName,
      tableIds: tableIds,
      managerPhone: managerPhone,
    );
  }

  // Remove waiter assignment from a table
  Future<void> removeWaiterFromTable(String tableId) async {
    await _dbService.removeWaiterFromTable(
      tableId,
      managerPhone: managerPhone,
    );
  }

  // Save/Edit waiter for this manager
  Future<void> saveWaiter(WaiterModel waiter) async {
    await _dbService.saveWaiter(
      waiter,
      managerPhone: managerPhone,
      managerUid: managerUid,
      managerEmail: managerEmail,
    );
  }

  // Delete waiter for this manager
  Future<void> deleteWaiter(String waiterId) async {
    await _dbService.deleteWaiter(
      waiterId,
      managerPhone: managerPhone,
    );
  }

  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? waiterId,
  }) async {
    await _dbService.acceptTableRequest(
      tableId: tableId,
      waiterName: waiterName,
      waiterId: waiterId,
      managerPhone: managerPhone,
      managerUid: managerUid,
    );
    await _bleService.acceptTableRequest(
      tableId: tableId,
      waiterName: waiterName,
      managerUid: managerUid,
    );
  }

  Future<void> resetTableStatus(String tableId) async {
    await _dbService.resetTableStatus(
      tableId,
      managerPhone: managerPhone,
    );
    await _bleService.resetTableStatus(tableId);
  }

  Future<void> resetAllTables() async {
    await _dbService.resetAllTables(
      managerPhone: managerPhone,
    );
    await _bleService.resetAllTables();
  }

  Future<void> triggerTableRequest(String tableId, {int? tableNumber}) async {
    await _dbService.triggerTableRequest(
      tableId,
      tableNumber: tableNumber,
      managerPhone: managerPhone,
      managerUid: managerUid,
      managerEmail: managerEmail,
    );
    await _bleService.triggerTableRequest(tableId, tableNumber: tableNumber);
  }

  void dispose() {
    _cloudRequestSub?.cancel();
  }
}
