import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/ble_service.dart';
import '../data/service_request_repository.dart';
import '../domain/table_model.dart';

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(() => service.dispose());
  return service;
});

final serviceRequestRepositoryProvider = Provider<ServiceRequestRepository>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  return ServiceRequestRepository(bleService);
});

// Real-time Stream of all Dynamic Hotel Tables (Discovered over BLE)
final tablesStreamProvider = StreamProvider<List<TableModel>>((ref) {
  final repo = ref.watch(serviceRequestRepositoryProvider);
  return repo.getTablesStream();
});

// BLE Scanning state
final bleScanningStreamProvider = StreamProvider<bool>((ref) {
  final ble = ref.watch(bleServiceProvider);
  return ble.isScanningStream;
});

// BLE Adapter state
final bleAdapterStateStreamProvider = StreamProvider<BluetoothAdapterState>((ref) {
  final ble = ref.watch(bleServiceProvider);
  return ble.adapterStateStream;
});

// Derived Providers for filtered Tables
final pendingTablesProvider = Provider<List<TableModel>>((ref) {
  final tablesAsync = ref.watch(tablesStreamProvider);
  return tablesAsync.value?.where((t) => t.isPending).toList() ?? [];
});

final acceptedTablesProvider = Provider<List<TableModel>>((ref) {
  final tablesAsync = ref.watch(tablesStreamProvider);
  return tablesAsync.value?.where((t) => t.isAccepted).toList() ?? [];
});

final idleTablesProvider = Provider<List<TableModel>>((ref) {
  final tablesAsync = ref.watch(tablesStreamProvider);
  return tablesAsync.value?.where((t) => t.isIdle).toList() ?? [];
});
