import '../../../core/services/ble_service.dart';
import '../../../core/services/firebase_realtime_service.dart';
import '../../waiter/domain/waiter_model.dart';
import '../domain/table_model.dart';

class ServiceRequestRepository {
  final BleService _bleService;
  final FirebaseRealtimeService _dbService;

  ServiceRequestRepository(this._bleService, this._dbService);

  // Stream all tables from Firebase Realtime Database
  Stream<List<TableModel>> getTablesStream() {
    return _dbService.getTablesStream();
  }

  // Stream only tables assigned to a specific waiter
  Stream<List<TableModel>> getTablesForWaiterStream(String waiterId) {
    return _dbService.getTablesForWaiterStream(waiterId);
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
