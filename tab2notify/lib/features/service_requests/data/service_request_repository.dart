import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/services/ble_service.dart';
import '../../../core/services/firebase_realtime_service.dart';
import '../../waiter/domain/waiter_model.dart';
import '../domain/table_model.dart';

class ServiceRequestRepository {
  final BleService _bleService;
  final FirebaseRealtimeService _dbService;

  ServiceRequestRepository(this._bleService, this._dbService) {
    // Forward BLE physical device discoveries to Firebase Realtime Database asynchronously
    _bleService.onDeviceDiscovered = (TableModel bleTable) {
      _dbService.syncBleDeviceStatus(
        tableId: bleTable.id,
        tableNumber: bleTable.tableNumber,
        status: bleTable.status,
        flag: bleTable.flag,
        isOnline: true,
      ).catchError((err) {
        debugPrint('[SYNC ERROR] Failed to sync BLE device to cloud: $err');
      });
    };

    _bleService.onDeviceLost = (String tableId) {
      _dbService.updateDeviceOnlineStatus(tableId, false).catchError((err) {
        debugPrint('[SYNC ERROR] Failed to update offline status: $err');
      });
    };
  }

  // Stream all tables with live merged BLE online status
  Stream<List<TableModel>> getTablesStream() {
    late StreamController<List<TableModel>> controller;
    StreamSubscription? dbSub;
    StreamSubscription? bleSub;
    List<TableModel> lastDbTables = [];

    List<TableModel> computeMerged() {
      if (lastDbTables.isEmpty) {
        return const [];
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
        _bleService.requestPermissionsAndStartScan();

        dbSub = _dbService.getTablesStream().listen(
          (dbList) {
            lastDbTables = dbList;
            if (!controller.isClosed) {
              controller.add(computeMerged());
            }
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

        bleSub = _bleService.tablesStream.listen(
          (_) {
            if (!controller.isClosed) {
              controller.add(computeMerged());
            }
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
        _bleService.requestPermissionsAndStartScan();

        dbSub = _dbService.getTablesForWaiterStream(waiterId).listen(
          (dbList) {
            lastDbTables = dbList;
            if (!controller.isClosed) {
              controller.add(computeMerged());
            }
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

        bleSub = _bleService.tablesStream.listen(
          (_) {
            if (!controller.isClosed) {
              controller.add(computeMerged());
            }
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

  // Stream registered waiters
  Stream<List<WaiterModel>> getWaitersStream() {
    return _dbService.getWaitersStream();
  }

  // Configure total tables (e.g. 20)
  Future<void> batchConfigureTables(int count) async {
    await _dbService.batchConfigureTables(count);
  }

  // Assign Waiter to tables
  Future<void> assignWaiterToTables({
    required String waiterId,
    required String waiterName,
    required List<String> tableIds,
  }) async {
    await _dbService.assignWaiterToTables(
      waiterId: waiterId,
      waiterName: waiterName,
      tableIds: tableIds,
    );
  }

  // Remove waiter assignment from a table
  Future<void> removeWaiterFromTable(String tableId) async {
    await _dbService.removeWaiterFromTable(tableId);
  }

  // Save/Edit waiter
  Future<void> saveWaiter(WaiterModel waiter) async {
    await _dbService.saveWaiter(waiter);
  }

  // Delete waiter
  Future<void> deleteWaiter(String waiterId) async {
    await _dbService.deleteWaiter(waiterId);
  }

  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? waiterId,
    String? managerUid,
  }) async {
    await _dbService.acceptTableRequest(
      tableId: tableId,
      waiterName: waiterName,
      waiterId: waiterId,
      managerUid: managerUid,
    );
    await _bleService.acceptTableRequest(
      tableId: tableId,
      waiterName: waiterName,
      managerUid: managerUid,
    );
  }

  Future<void> resetTableStatus(String tableId) async {
    await _dbService.resetTableStatus(tableId);
    await _bleService.resetTableStatus(tableId);
  }

  Future<void> triggerTableRequest(String tableId, {int? tableNumber}) async {
    await _dbService.triggerTableRequest(tableId, tableNumber: tableNumber);
    await _bleService.triggerTableRequest(tableId, tableNumber: tableNumber);
  }
}
