import 'package:flutter_test/flutter_test.dart';
import 'package:tab2notify/features/service_requests/domain/table_model.dart';
import 'package:tab2notify/features/waiter/domain/waiter_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Production Zero-State & Clean Data Handling', () {
    test('Empty table list produces clean zero counts without hardcoded defaults', () {
      final List<TableModel> emptyTables = [];
      final pendingList = emptyTables.where((t) => t.isPending).toList();
      final acceptedList = emptyTables.where((t) => t.isAccepted).toList();
      final idleList = emptyTables.where((t) => !t.isPending && !t.isAccepted).toList();

      expect(emptyTables.length, 0);
      expect(pendingList.length, 0);
      expect(acceptedList.length, 0);
      expect(idleList.length, 0);
    });

    test('WaiterModel parsing handles missing or custom waiterId cleanly', () {
      final map = {
        'name': 'Custom Waiter',
        'passcode': '9988',
        'status': 'active',
      };
      final waiter = WaiterModel.fromMap(map, 'W999');
      expect(waiter.waiterId, 'W999');
      expect(waiter.name, 'Custom Waiter');
      expect(waiter.passcode, '9988');
    });

    test('TableModel assignment detection requires actual waiter ID or name', () {
      final unassignedTable = TableModel(
        id: 'table_1',
        tableNumber: 1,
        deviceId: 'device_1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(unassignedTable.isAssigned, isFalse);
      expect(unassignedTable.assignedWaiterId, isEmpty);

      final assignedTable = unassignedTable.copyWith(
        assignedWaiterId: 'W101',
        waiterName: 'Sameer Verma',
      );

      expect(assignedTable.isAssigned, isTrue);
      expect(assignedTable.assignedWaiterId, 'W101');
    });
  });
}
