import '../../../core/services/ble_service.dart';
import '../domain/table_model.dart';

class ServiceRequestRepository {
  final BleService _bleService;

  ServiceRequestRepository(this._bleService);

  // Dynamic Tables Stream from BLE Scanner
  Stream<List<TableModel>> getTablesStream() {
    return _bleService.tablesStream;
  }

  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? managerUid,
  }) async {
    await _bleService.acceptTableRequest(
      tableId: tableId,
      waiterName: waiterName,
      managerUid: managerUid,
    );
  }

  Future<void> resetTableStatus(String tableId) async {
    await _bleService.resetTableStatus(tableId);
  }

  Future<void> triggerTableRequest(String tableId, {int? tableNumber}) async {
    await _bleService.triggerTableRequest(tableId, tableNumber: tableNumber);
  }
}
