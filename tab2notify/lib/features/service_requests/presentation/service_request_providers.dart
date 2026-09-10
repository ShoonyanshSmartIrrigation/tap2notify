import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/ble_service.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../waiter/domain/waiter_model.dart';
import '../data/service_request_repository.dart';
import '../domain/service_request_model.dart';
import '../domain/table_model.dart';

final bleServiceProvider = Provider<BleService>((ref) {
  return BleService();
});

final serviceRequestRepositoryProvider = Provider<ServiceRequestRepository>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  final dbService = ref.watch(firebaseRealtimeServiceProvider);
  final currentWaiter = ref.watch(currentLoggedWaiterProvider);

  ServiceRequestRepository repo;
  // If a waiter floor session is active, construct repository directly from waiter credentials
  if (currentWaiter != null && currentWaiter.managerPhone.isNotEmpty) {
    repo = ServiceRequestRepository(
      bleService,
      dbService,
      managerPhone: currentWaiter.managerPhone,
      managerUid: currentWaiter.managerUid,
      managerEmail: currentWaiter.managerEmail,
      currentWaiterId: currentWaiter.waiterId,
    );
  } else {
    // Otherwise, construct from authenticated manager's profile
    final authUser = ref.watch(authStateProvider).value;
    final profileAsync = ref.watch(currentUserProfileProvider);

    final managerPhone = (profileAsync.value?.phone.isNotEmpty ?? false)
        ? profileAsync.value!.phone
        : (authUser?.phoneNumber ?? authUser?.uid ?? '');

    final managerUid = authUser?.uid ?? '';
    final managerEmail = profileAsync.value?.email ?? authUser?.email;

    repo = ServiceRequestRepository(
      bleService,
      dbService,
      managerPhone: managerPhone,
      managerUid: managerUid,
      managerEmail: managerEmail,
    );
  }

  ref.onDispose(() => repo.dispose());
  return repo;
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

// Real-time Stream of Service Requests
final serviceRequestsStreamProvider = StreamProvider<List<ServiceRequestModel>>((ref) {
  final repo = ref.watch(serviceRequestRepositoryProvider);
  final dbService = ref.watch(firebaseRealtimeServiceProvider);
  return dbService.getServiceRequestsStream(managerPhone: repo.managerPhone);
});

class CurrentLoggedWaiterNotifier extends Notifier<WaiterModel?> {
  static const String _storageKey = 'active_waiter_session';

  @override
  WaiterModel? build() {
    try {
      final prefs = ref.watch(sharedPreferencesProvider);
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final wId = map['waiterId']?.toString() ?? map['id']?.toString() ?? '';
        return WaiterModel.fromMap(map, wId);
      }
    } catch (e) {
      debugPrint('[WAITER_SESSION] Error loading saved waiter session: $e');
    }
    return null;
  }

  Future<void> setWaiter(WaiterModel? waiter) async {
    state = waiter;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
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

