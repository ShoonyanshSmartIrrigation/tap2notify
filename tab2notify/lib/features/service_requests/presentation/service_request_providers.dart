import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/ble_service.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../waiter/domain/waiter_model.dart';
import '../data/service_request_repository.dart';
import '../domain/table_model.dart';

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(() => service.dispose());
  return service;
});

final serviceRequestRepositoryProvider = Provider<ServiceRequestRepository>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  final dbService = ref.watch(firebaseRealtimeServiceProvider);
  return ServiceRequestRepository(bleService, dbService);
});

// Real-time Stream of all Dynamic Hotel Tables (from Firebase Realtime Database)
final tablesStreamProvider = StreamProvider<List<TableModel>>((ref) {
  final repo = ref.watch(serviceRequestRepositoryProvider);
  return repo.getTablesStream();
});

// Real-time Stream of all Registered Waiters
final waitersStreamProvider = StreamProvider<List<WaiterModel>>((ref) {
  final repo = ref.watch(serviceRequestRepositoryProvider);
  return repo.getWaitersStream();
});

// Real-time Stream of Tables for a Specific Waiter
final waiterTablesStreamProvider = StreamProvider.family<List<TableModel>, String>((ref, waiterId) {
  final repo = ref.watch(serviceRequestRepositoryProvider);
  return repo.getTablesForWaiterStream(waiterId);
});

class CurrentLoggedWaiterNotifier extends Notifier<WaiterModel?> {
  static const String _storageKey = 'active_waiter_session';

  @override
  WaiterModel? build() {
    _loadPersistedWaiter();
    return null;
  }

  Future<void> _loadPersistedWaiter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final waiter = WaiterModel.fromMap(map, map['waiterId']?.toString() ?? 'W001');
        state = waiter;
      }
    } catch (e) {
      debugPrint('[WAITER_SESSION] Error loading saved waiter session: $e');
    }
  }

  Future<void> setWaiter(WaiterModel? waiter) async {
    state = waiter;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (waiter != null) {
        await prefs.setString(_storageKey, jsonEncode(waiter.toMap()));
      } else {
        await prefs.remove(_storageKey);
      }
    } catch (e) {
      debugPrint('[WAITER_SESSION] Error saving waiter session: $e');
    }
  }
}

// Current Waiter Session State (for Waiter Dashboard)
final currentLoggedWaiterProvider =
    NotifierProvider<CurrentLoggedWaiterNotifier, WaiterModel?>(
  CurrentLoggedWaiterNotifier.new,
);

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

