import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/services/ble_service.dart';
import '../../../core/services/device_credential_service.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/firebase_realtime_service.dart';
import '../../../core/services/notification_audio_service.dart';
import '../../waiter/domain/waiter_model.dart';
import '../domain/table_model.dart';

class ServiceRequestRepository {
  final BleService _bleService;
  final FirebaseRealtimeService _dbService;
  final DeviceCredentialService? _credentialService;
  final String managerPhone;
  final String managerUid;
  final String? managerEmail;
  final String currentWaiterId;

  static final Map<String, int> _lastNotifiedTime = {};
  static final Set<String> _escalatedTableIds = {};
  static final Map<String, int> _pendingEntryTimestamps = {};
  static final Set<String> _notifiedPendingTableKeys = {};
  static final Map<String, int> _lastNotifiedRequestSentAt = {};
  List<TableModel> _cachedTables = [];
  Timer? _managerEscalationTicker;
  StreamSubscription<List<TableModel>>? _cloudRequestSub;

  static String _cleanKey(dynamic rawId) {
    if (rawId == null) return '';
    final str = rawId.toString().trim();
    if (str.isEmpty) return '';
    final lower = str.toLowerCase();
    String stripped = str;
    if (lower.startsWith('table_')) {
      stripped = str.substring(6);
    } else if (lower.startsWith('table')) {
      stripped = str.substring(5);
    } else if (lower.startsWith('device_')) {
      stripped = str.substring(7);
    } else if (lower.startsWith('device')) {
      stripped = str.substring(6);
    }
    final clean = stripped.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
    return clean;
  }

  static Set<String> _getNormalizedKeys(String tableId, [dynamic tableNumber]) {
    final keys = <String>{};
    final trimmedId = tableId.trim();
    if (trimmedId.isNotEmpty) {
      keys.add(trimmedId.toLowerCase());
      final clean = _cleanKey(trimmedId);
      if (clean.isNotEmpty) {
        keys.add(clean.toLowerCase());
        keys.add('table_${clean.toLowerCase()}');
      }
      final digits = trimmedId.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) {
        keys.add(digits);
        keys.add('table_$digits');
      }
    }
    if (tableNumber != null) {
      final tStr = tableNumber.toString().trim();
      if (tStr.isNotEmpty) {
        keys.add(tStr.toLowerCase());
        final clean = _cleanKey(tStr);
        if (clean.isNotEmpty) {
          keys.add(clean.toLowerCase());
          keys.add('table_${clean.toLowerCase()}');
        }
        final digits = tStr.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.isNotEmpty) {
          keys.add(digits);
          keys.add('table_$digits');
        }
      }
    }
    return keys;
  }

  static void _clearNotifiedPending(String tableId, [dynamic tableNumber]) {
    final keys = _getNormalizedKeys(tableId, tableNumber);
    for (final k in keys) {
      _notifiedPendingTableKeys.remove(k);
      _lastNotifiedRequestSentAt.remove(k);
      _lastNotifiedTime.remove(k);
    }
  }

  @visibleForTesting
  static void resetNotificationStateForTesting() {
    _notifiedPendingTableKeys.clear();
    _lastNotifiedRequestSentAt.clear();
    _lastNotifiedTime.clear();
    _escalatedTableIds.clear();
    _pendingEntryTimestamps.clear();
  }


  ServiceRequestRepository(
    this._bleService,
    this._dbService, {
    DeviceCredentialService? credentialService,
    this.managerPhone = '',
    this.managerUid = '',
    this.managerEmail,
    this.currentWaiterId = '',
  }) : _credentialService = credentialService {
    // Set active manager session in GatewayWifiService
    if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
      _bleService.setActiveManager(
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
    }

    // Pre-populate dynamic in-memory credentials from secure local storage for this manager
    if (_credentialService != null) {
      final savedCreds = _credentialService.getAllCredentials(
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
      savedCreds.forEach((devId, pwd) {
        _bleService.registerStoredCredential(
          devId,
          pwd,
          managerPhone: managerPhone,
          managerUid: managerUid,
        );
        _bleService.authorizeTableForManager(
          tableId: devId,
          password: pwd,
          managerPhone: managerPhone,
          managerUid: managerUid,
        );
      });
    }

    // Forward BLE physical device discoveries to Firebase Realtime Database asynchronously
    _bleService.onDeviceDiscovered = (TableModel bleTable) {
      debugPrint(
        '[BLE DISCOVERED HOOK] Table ${bleTable.tableNumber} (${bleTable.id}) status=${bleTable.status} flag=${bleTable.flag} managerPhone=$managerPhone currentWaiterId=$currentWaiterId',
      );
      // Instant Native Notification Alert for urgent service requests (STRICTLY for UNLOCKED tables)
      final bool isTableUnlockedForThis = isTableAuthorizedForThisManager(bleTable);
      if (bleTable.flag == 0 && isTableUnlockedForThis) {
        _pendingEntryTimestamps[bleTable.id] ??=
            bleTable.requestSentAt ?? DateTime.now().millisecondsSinceEpoch;
        _triggerRequestNotification(
          tableId: bleTable.id,
          tableNumber: bleTable.tableNumber,
          assignedWaiterId: bleTable.assignedWaiterId,
          waiterName: bleTable.waiterName,
          isUnlocked: isTableUnlockedForThis,
          requestSentAt: bleTable.requestSentAt,
        );
      } else if (bleTable.flag != 0) {
        _pendingEntryTimestamps.remove(bleTable.id);
        _escalatedTableIds.remove(bleTable.id);
        _clearNotifiedPending(bleTable.id, bleTable.tableNumber);
      }

      if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
        _dbService
            .syncBleDeviceStatus(
              tableId: bleTable.id,
              tableNumber: bleTable.tableNumber,
              status: bleTable.status,
              flag: bleTable.flag,
              isOnline: true,
              managerPhone: managerPhone,
              managerUid: managerUid,
              managerEmail: managerEmail,
            )
            .catchError((err) {
              debugPrint(
                '[SYNC ERROR] Failed to sync BLE device to cloud: $err',
              );
            });
      }
    };

    _bleService.onDeviceLost = (String tableId) {
      if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
        _dbService
            .updateDeviceOnlineStatus(
              tableId,
              false,
              managerPhone: managerPhone,
            )
            .catchError((err) {
              debugPrint('[SYNC ERROR] Failed to update offline status: $err');
            });
      }
    };

    // Listen to RTDB tables to alert if status is set to pending from cloud/web
    if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
      _startCloudRequestListener();
    }

    // Always start escalation ticker for manager session (works in pure Wi-Fi mode & cloud)
    if (currentWaiterId.isEmpty) {
      _managerEscalationTicker = Timer.periodic(const Duration(seconds: 1), (
        _,
      ) {
        _checkManagerEscalation(_cachedTables);
      });
    }
  }

  /// Determines if a table/device is authorized and unlocked for THIS specific manager
  bool isTableAuthorizedForThisManager(TableModel t) {
    final cleanId = _bleService.cleanTableNum(t.tableNumber ?? t.id);
    final numPart = cleanId.replaceAll(RegExp(r'[^0-9]'), '');

    // 0. Foreign manager isolation check:
    // If the table explicitly belongs to a different manager, REJECT access.
    if (t.managerPhone.isNotEmpty && managerPhone.isNotEmpty && t.managerPhone != managerPhone) {
      return false;
    }
    if (t.managerUid.isNotEmpty && managerUid.isNotEmpty && t.managerUid != managerUid) {
      return false;
    }

    // 1. For a WAITER session: Waiters rely on the manager having unlocked and assigned the table
    if (currentWaiterId.isNotEmpty) {
      return t.isUnlocked;
    }

    // 2. If this manager's cloud RTDB record is unlocked AND strictly owned by this manager
    final bool isOwnedByThisManager = (t.managerPhone.isNotEmpty && t.managerPhone == managerPhone) ||
        (t.managerUid.isNotEmpty && t.managerUid == managerUid) ||
        (t.unlockedBy != null && t.unlockedBy!.isNotEmpty && (t.unlockedBy == managerUid || t.unlockedBy == managerPhone)) ||
        (t.managerPhone.isEmpty && t.managerUid.isEmpty && managerPhone.isEmpty && managerUid.isEmpty);

    if (isOwnedByThisManager && t.isUnlocked) {
      return true;
    }

    // 2. If this manager has saved credentials in DeviceCredentialService
    if (_credentialService != null) {
      if (_credentialService.getCredential(
            cleanId,
            managerPhone: managerPhone,
            managerUid: managerUid,
          ) !=
          null ||
          (numPart.isNotEmpty &&
              _credentialService.getCredential(
                    numPart,
                    managerPhone: managerPhone,
                    managerUid: managerUid,
                  ) !=
                  null)) {
        return true;
      }
    }

    // 3. If local GatewayWifiService has manager authorization for this manager
    if (_bleService.isTableUnlockedForManager(
          t.id,
          managerPhone: managerPhone,
          managerUid: managerUid,
        ) ||
        _bleService.isTableUnlockedForManager(
          cleanId,
          managerPhone: managerPhone,
          managerUid: managerUid,
        ) ||
        (numPart.isNotEmpty &&
            _bleService.isTableUnlockedForManager(
              numPart,
              managerPhone: managerPhone,
              managerUid: managerUid,
            ))) {
      return true;
    }

    return false;
  }

  bool _areTableListsEqual(List<TableModel> a, List<TableModel> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final tA = a[i];
      final tB = b[i];
      if (tA.id != tB.id ||
          tA.status != tB.status ||
          tA.flag != tB.flag ||
          tA.isUnlocked != tB.isUnlocked ||
          tA.isDeviceOnline != tB.isDeviceOnline ||
          tA.assignedWaiterId != tB.assignedWaiterId ||
          tA.waiterName != tB.waiterName ||
          tA.requestSentAt != tB.requestSentAt ||
          tA.acceptedAt != tB.acceptedAt) {
        return false;
      }
    }
    return true;
  }

  void _startCloudRequestListener() {
    _cloudRequestSub?.cancel();
    _cloudRequestSub = _dbService
        .getTablesStream(
          managerPhone: managerPhone,
          managerUid: managerUid,
          managerEmail: managerEmail,
        )
        .listen(
          (tables) {
            _cachedTables = tables;
            for (final table in tables) {
              _bleService.syncTableFromCloud(
                table,
                managerPhone: managerPhone,
                managerUid: managerUid,
              );
              if (table.isPending) {
                if (isTableAuthorizedForThisManager(table)) {
                  _triggerRequestNotification(
                    tableId: table.id,
                    tableNumber: table.tableNumber,
                    assignedWaiterId: table.assignedWaiterId,
                    waiterName: table.waiterName,
                    isUnlocked: table.isUnlocked,
                    requestSentAt: table.requestSentAt,
                  );
                }
              } else {
                _clearNotifiedPending(table.id, table.tableNumber);
              }
            }
            if (currentWaiterId.isEmpty) {
              _checkManagerEscalation(tables);
            }
          },
          onError: (e) {
            debugPrint('[CLOUD NOTIF LISTENER] Error: $e');
          },
        );
  }

  void _checkManagerEscalation(List<TableModel> tables) {
    if (currentWaiterId.isNotEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Merge tables with _bleService.currentTables so local Wi-Fi tables are always checked
    final allActiveTables = <String, TableModel>{};
    for (final t in tables) {
      allActiveTables[t.id] = t;
    }
    for (final t in _bleService.currentTables) {
      if (allActiveTables.containsKey(t.id)) {
        final existing = allActiveTables[t.id]!;
        final int dbTime = existing.updatedAt ?? existing.createdAt;
        final int bleTime = t.updatedAt ?? t.createdAt;
        final bool useBle = bleTime > dbTime;

        final bool isOnlineResolved = _bleService.connectionStatus == GatewayConnectionStatus.connected
            ? (t.isDeviceOnline || _bleService.isTableOnline(t.id))
            : (t.isDeviceOnline || existing.isDeviceOnline);

        final bool authorized = isTableAuthorizedForThisManager(existing) ||
            isTableAuthorizedForThisManager(t);

        allActiveTables[t.id] = existing.copyWith(
          flag: useBle ? t.flag : existing.flag,
          status: useBle ? t.status : existing.status,
          isUnlocked: authorized,
          isDeviceOnline: isOnlineResolved,
          requestSentAt: t.requestSentAt ?? existing.requestSentAt,
        );
      } else {
        allActiveTables[t.id] = t.copyWith(
          isUnlocked: isTableAuthorizedForThisManager(t),
        );
      }
    }

    for (final table in allActiveTables.values) {
      final isUnlocked = isTableAuthorizedForThisManager(table);
      if (table.isPending && isUnlocked) {
        final effectiveSentTime =
            table.requestSentAt ?? _pendingEntryTimestamps[table.id] ?? now;
        _pendingEntryTimestamps[table.id] = effectiveSentTime;

        final elapsed = now - effectiveSentTime;
        if (elapsed >= 20000 && !_escalatedTableIds.contains(table.id)) {
          _escalatedTableIds.add(table.id);
          debugPrint(
            '[MANAGER ESCALATION] Table ${table.tableNumber} pending for ${elapsed ~/ 1000}s >= 20s. Alerting manager.',
          );
          NotificationAudioService().playManagerEscalationPrompt(
            tableId: table.id,
          );
          FCMService().showNativeNotification(
            title: '⚠️ Unattended Table ${table.tableNumber} Alert!',
            body:
                'Table ${table.tableNumber} (${table.waiterName.isNotEmpty ? table.waiterName : "Unassigned"}) has been pending for >20s!',
            requestId: table.id,
            tableNumber: table.tableNumber,
            channelId: 'manager_escalation_channel',
            sound: 'please_hold',
          );
        }
      } else {
        _pendingEntryTimestamps.remove(table.id);
        _escalatedTableIds.remove(table.id);
      }
    }
  }

  void _triggerRequestNotification({
    required String tableId,
    required dynamic tableNumber,
    String assignedWaiterId = '',
    String waiterName = '',
    bool isUnlocked = false,
    int? requestSentAt,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final keys = _getNormalizedKeys(tableId, tableNumber);

    // Check if any normalized key for this table was already notified for this active pending session
    final bool alreadyNotified = keys.any((k) => _notifiedPendingTableKeys.contains(k));

    // A sound/notification must ONLY play when a genuinely new pending request is received,
    // NEVER when an existing request is accepted, updated, refreshed, or re-rendered.
    if (alreadyNotified) {
      debugPrint(
        '[NOTIFICATION SUPPRESSED] Table $tableNumber ($tableId) is already pending and notified. Suppressing audio & notif.',
      );
      return;
    }

    // Debounce duplicate alerts across all keys within 8 seconds
    int lastAlertTime = 0;
    for (final k in keys) {
      final t = _lastNotifiedTime[k];
      if (t != null && t > lastAlertTime) lastAlertTime = t;
    }
    if (now - lastAlertTime < 8000) return;

    // 1. If user is a MANAGER: Table service requests are intended for Waiters, NOT the Manager.
    // Suppress waiter table alerts on the manager's device.
    if (currentWaiterId.isEmpty) {
      debugPrint(
        '[NOTIF SCOPE] Table $tableNumber service request suppressed for Manager (waiter-only alert).',
      );
      return;
    }

    // 2. If user is a WAITER: Strictly verify the table is unlocked by manager
    final normKey = tableNumber.toString();
    final cachedTable = _cachedTables.cast<TableModel?>().firstWhere(
      (t) => t?.id == tableId || t?.tableNumber.toString() == normKey,
      orElse: () => null,
    );
    final tableUnlocked =
        isUnlocked ||
        (cachedTable?.isUnlocked ?? false) ||
        _bleService.isTableUnlocked(tableId);
    if (!tableUnlocked) {
      debugPrint(
        '[NOTIF SCOPE] Table $tableNumber is LOCKED. Waiter alert suppressed.',
      );
      return;
    }

    // 3. Strictly verify the table is assigned to THIS waiter.
    final isAssigned =
        (assignedWaiterId.isNotEmpty && assignedWaiterId == currentWaiterId) ||
        waiterName.contains('($currentWaiterId)') ||
        (waiterName.isNotEmpty &&
            (waiterName == currentWaiterId ||
                waiterName.contains(currentWaiterId))) ||
        (cachedTable != null &&
            ((cachedTable.assignedWaiterId.isNotEmpty &&
                    cachedTable.assignedWaiterId == currentWaiterId) ||
                cachedTable.waiterName.contains('($currentWaiterId)') ||
                cachedTable.waiterName == currentWaiterId));

    if (!isAssigned) {
      debugPrint(
        '[NOTIF SCOPE] Table $tableNumber not assigned to Waiter $currentWaiterId. Alert suppressed.',
      );
      return;
    }

    // Mark all keys as notified for this active pending session
    for (final k in keys) {
      _notifiedPendingTableKeys.add(k);
      _lastNotifiedTime[k] = now;
      if (requestSentAt != null && requestSentAt > 0) {
        _lastNotifiedRequestSentAt[k] = requestSentAt;
      } else {
        _lastNotifiedRequestSentAt[k] = now;
      }
    }

    debugPrint(
      '[NOTIFICATION TRIGGER] Showing OS notification & playing audio for Table $tableNumber ($tableId) to Waiter $currentWaiterId',
    );

    // Play Incoming_Prompt.mp3 audio exclusively for THIS assigned waiter
    NotificationAudioService().playIncomingRequestPrompt(tableId: tableId);

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
      debugPrint(
        '[NOTIF SCOPE] Manager alert suppressed on Waiter device ($currentWaiterId)',
      );
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
        return _bleService.currentTables.map((bleTable) {
          final isAuthorized = isTableAuthorizedForThisManager(bleTable);
          final bool isHwLocked = bleTable.flag == -2;
          return bleTable.copyWith(isUnlocked: !isHwLocked && isAuthorized);
        }).toList();
      }
      final merged = lastDbTables.map((t) {
        final isBleOnline = _bleService.isTableOnline(t.id) ||
            _bleService.isTableOnline(t.tableNumber.toString());
        final liveBleTable = _bleService.getLiveBleTable(t.id) ??
            _bleService.getLiveBleTable(t.tableNumber.toString());

        final bool isAuthorizedForThisManager = isTableAuthorizedForThisManager(t);
        final bool isHardwareLocked = liveBleTable?.flag == -2;
        final bool isUnlocked = !isHardwareLocked && isAuthorizedForThisManager;

        final bool effectiveOnline;
        if (_bleService.connectionStatus == GatewayConnectionStatus.connected) {
          effectiveOnline = liveBleTable != null
              ? liveBleTable.isDeviceOnline
              : isBleOnline;
        } else {
          effectiveOnline = isBleOnline || t.isDeviceOnline || (liveBleTable?.isDeviceOnline ?? false);
        }

        if (liveBleTable != null) {
          final int dbTime = t.updatedAt ?? t.createdAt;
          final int bleTime = liveBleTable.updatedAt ?? liveBleTable.createdAt;
          final bool useBle = bleTime > dbTime;
          final int resolvedFlag = useBle ? liveBleTable.flag : t.flag;
          final String resolvedStatus = useBle ? liveBleTable.status : t.status;

          final int? reqSentAt = resolvedFlag == 0
              ? (liveBleTable.requestSentAt ?? t.requestSentAt ?? dbTime)
              : (resolvedFlag == 1 ? (liveBleTable.requestSentAt ?? t.requestSentAt) : null);

          final int? accAt = resolvedFlag == 1
              ? (liveBleTable.acceptedAt ?? t.acceptedAt ?? (useBle ? bleTime : dbTime))
              : null;

          return t.copyWith(
            isDeviceOnline: effectiveOnline,
            status: resolvedStatus,
            flag: resolvedFlag,
            isUnlocked: isUnlocked,
            requestSentAt: reqSentAt,
            acceptedAt: accAt,
            waiterName: t.waiterName.isNotEmpty
                ? t.waiterName
                : liveBleTable.waiterName,
            assignedWaiterId: t.assignedWaiterId.isNotEmpty
                ? t.assignedWaiterId
                : liveBleTable.assignedWaiterId,
          );
        }
        return t.copyWith(isDeviceOnline: effectiveOnline, isUnlocked: isUnlocked);
      }).toList();

      for (final bleTable in _bleService.currentTables) {
        if (!merged.any(
          (m) =>
              m.id == bleTable.id ||
              m.tableNumber.toString() == bleTable.tableNumber.toString(),
        )) {
          final isAuthorized = isTableAuthorizedForThisManager(bleTable);
          final bool isHwLocked = bleTable.flag == -2;
          merged.add(bleTable.copyWith(isUnlocked: !isHwLocked && isAuthorized));
        }
      }
      merged.sort((a, b) {
        final aNum = int.tryParse(a.tableNumber.toString());
        final bNum = int.tryParse(b.tableNumber.toString());
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }
        return a.tableNumber.toString().compareTo(b.tableNumber.toString());
      });
      return merged;
    }

    controller = StreamController<List<TableModel>>(
      onListen: () {
        List<TableModel>? lastEmitted;
        void emitMerged() {
          if (controller.isClosed) return;
          final merged = computeMerged();
          if (lastEmitted != null && _areTableListsEqual(lastEmitted!, merged)) {
            return;
          }
          lastEmitted = merged;
          controller.add(merged);
        }

        dbSub = _dbService
            .getTablesStream(
              managerPhone: managerPhone,
              managerUid: managerUid,
              managerEmail: managerEmail,
            )
            .listen(
              (dbList) {
                lastDbTables = dbList;
                for (final t in dbList) {
                  _bleService.syncTableFromCloud(
                    t,
                    managerPhone: managerPhone,
                    managerUid: managerUid,
                  );
                }
                Future(() {
                  emitMerged();
                });
              },
              onError: (e) {
                Future(() {
                  if (!controller.isClosed) controller.addError(e);
                });
              },
            );

        bleSub = _bleService.tablesStream.listen((_) {
          Future(() {
            emitMerged();
          });
        });
      },
      onCancel: () {
        dbSub?.cancel();
        bleSub?.cancel();
      },
    );

    return controller.stream;
  }

  // Stream only tables assigned to a specific waiter with live merged BLE online status (Strictly Unlocked only)
  Stream<List<TableModel>> getTablesForWaiterStream(String waiterId) {
    late StreamController<List<TableModel>> controller;
    StreamSubscription? dbSub;
    StreamSubscription? bleSub;
    List<TableModel> lastDbTables = [];

    List<TableModel> computeMerged() {
      if (lastDbTables.isEmpty) {
        return _bleService.currentTables.where((t) {
          final isUnlocked = isTableAuthorizedForThisManager(t);
          return isUnlocked &&
              ((t.assignedWaiterId.isNotEmpty &&
                      t.assignedWaiterId == waiterId) ||
                  t.waiterName.contains('($waiterId)') ||
                  (t.waiterName.isNotEmpty &&
                      (t.waiterName == waiterId ||
                          t.waiterName.contains(waiterId))));
        }).toList();
      }
      final merged = lastDbTables
          .where((t) => isTableAuthorizedForThisManager(t))
          .map((t) {
            final isBleOnline = _bleService.isTableOnline(t.id) ||
                _bleService.isTableOnline(t.tableNumber.toString());
            final liveBleTable = _bleService.getLiveBleTable(t.id) ??
                _bleService.getLiveBleTable(t.tableNumber.toString());
            final bool isAuthorized = isTableAuthorizedForThisManager(t);
            final bool isUnlocked = isAuthorized;
            final bool effectiveOnline;
            if (_bleService.connectionStatus == GatewayConnectionStatus.connected) {
              effectiveOnline = liveBleTable != null
                  ? liveBleTable.isDeviceOnline
                  : isBleOnline;
            } else {
              effectiveOnline = isBleOnline || t.isDeviceOnline || (liveBleTable?.isDeviceOnline ?? false);
            }

            if (liveBleTable != null) {
              final int dbTime = t.updatedAt ?? t.createdAt;
              final int bleTime = liveBleTable.updatedAt ?? liveBleTable.createdAt;
              final bool useBle = bleTime > dbTime;
              final int resolvedFlag = useBle ? liveBleTable.flag : t.flag;
              final String resolvedStatus = useBle ? liveBleTable.status : t.status;

              final int? reqSentAt = resolvedFlag == 0
                  ? (liveBleTable.requestSentAt ?? t.requestSentAt ?? dbTime)
                  : (resolvedFlag == 1 ? (liveBleTable.requestSentAt ?? t.requestSentAt) : null);

              final int? accAt = resolvedFlag == 1
                  ? (liveBleTable.acceptedAt ?? t.acceptedAt ?? (useBle ? bleTime : dbTime))
                  : null;

              return t.copyWith(
                isDeviceOnline: effectiveOnline,
                status: resolvedStatus,
                flag: resolvedFlag,
                isUnlocked: isUnlocked,
                requestSentAt: reqSentAt,
                acceptedAt: accAt,
                waiterName: t.waiterName.isNotEmpty
                    ? t.waiterName
                    : liveBleTable.waiterName,
                assignedWaiterId: t.assignedWaiterId.isNotEmpty
                    ? t.assignedWaiterId
                    : liveBleTable.assignedWaiterId,
              );
            }
            return t.copyWith(
              isDeviceOnline: effectiveOnline,
              isUnlocked: isUnlocked,
            );
          })
          .where((t) => t.isUnlocked)
          .toList();

      for (final bleTable in _bleService.currentTables) {
        final isUnlocked = isTableAuthorizedForThisManager(bleTable) && bleTable.flag != -2;
        final isAssigned =
            (bleTable.assignedWaiterId.isNotEmpty &&
                bleTable.assignedWaiterId == waiterId) ||
            bleTable.waiterName.contains('($waiterId)') ||
            (bleTable.waiterName.isNotEmpty &&
                (bleTable.waiterName == waiterId ||
                    bleTable.waiterName.contains(waiterId)));
        if (isUnlocked &&
            isAssigned &&
            !merged.any(
              (m) =>
                  m.id == bleTable.id ||
                  m.tableNumber.toString() == bleTable.tableNumber.toString(),
            )) {
          merged.add(bleTable.copyWith(isUnlocked: true));
        }
      }

      merged.sort((a, b) {
        final aNum = int.tryParse(a.tableNumber.toString());
        final bNum = int.tryParse(b.tableNumber.toString());
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }
        return a.tableNumber.toString().compareTo(b.tableNumber.toString());
      });
      return merged;
    }

    controller = StreamController<List<TableModel>>(
      onListen: () {
        List<TableModel>? lastEmitted;
        void emitMerged() {
          if (controller.isClosed) return;
          final merged = computeMerged();
          if (lastEmitted != null && _areTableListsEqual(lastEmitted!, merged)) {
            return;
          }
          lastEmitted = merged;
          controller.add(merged);
        }

        dbSub = _dbService
            .getTablesForWaiterStream(
              waiterId,
              managerPhone: managerPhone,
              managerUid: managerUid,
              managerEmail: managerEmail,
            )
            .listen(
              (dbList) {
                lastDbTables = dbList;
                for (final t in dbList) {
                  _bleService.assignWaiterLocally(t.id, waiterId, t.waiterName);
                  _bleService.syncTableFromCloud(
                    t,
                    managerPhone: managerPhone,
                    managerUid: managerUid,
                  );
                }
                Future(() {
                  emitMerged();
                });
              },
              onError: (e) {
                Future(() {
                  if (!controller.isClosed) controller.addError(e);
                });
              },
            );

        bleSub = _bleService.tablesStream.listen((_) {
          Future(() {
            emitMerged();
          });
        });
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
    // Admission check: Manager can only assign waiters to tables they have authorized and unlocked
    final unauthorized = tableIds.where((tableId) {
      final cleanId = _bleService.cleanTableNum(tableId);
      final numPart = cleanId.replaceAll(RegExp(r'[^0-9]'), '');

      // 1. Explicitly authorized in GatewayWifiService for this manager
      if (_bleService.isTableUnlockedForManager(
            tableId,
            managerPhone: managerPhone,
            managerUid: managerUid,
          ) ||
          _bleService.isTableUnlockedForManager(
            cleanId,
            managerPhone: managerPhone,
            managerUid: managerUid,
          )) {
        return false;
      }

      // 2. Verified credentials exist for this manager
      if (_credentialService != null &&
          (_credentialService.getCredential(
                cleanId,
                managerPhone: managerPhone,
                managerUid: managerUid,
              ) !=
              null ||
              (numPart.isNotEmpty &&
                  _credentialService.getCredential(
                        numPart,
                        managerPhone: managerPhone,
                        managerUid: managerUid,
                      ) !=
                      null))) {
        return false;
      }

      // 3. If in cached tables, verify this manager's authorization
      final cached = _cachedTables.cast<TableModel?>().firstWhere(
        (t) => t != null && (t.id == tableId || t.tableNumber.toString() == cleanId),
        orElse: () => null,
      );
      if (cached != null) {
        return !isTableAuthorizedForThisManager(cached);
      }

      // 4. If table is physically locked in local Gateway BLE service without credentials
      final liveTable = _bleService.getLiveTable(tableId);
      if (liveTable != null && (liveTable.flag == -2 || liveTable.status == 'locked')) {
        return true;
      }

      return false;
    }).toList();

    if (unauthorized.isNotEmpty) {
      throw Exception(
        'Cannot assign waiter: The following tables are not unlocked or authorized by you: ${unauthorized.join(", ")}. Please unlock each table with its password first.',
      );
    }

    for (final tableId in tableIds) {
      _bleService.assignWaiterLocally(tableId, waiterId, waiterName);
      _bleService.authorizeTableForManager(
        tableId: tableId,
        password: '',
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
    }
    if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
      await _dbService.assignWaiterToTables(
        waiterId: waiterId,
        waiterName: waiterName,
        tableIds: tableIds,
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
    }
  }

  // Remove waiter assignment from a table
  Future<void> removeWaiterFromTable(String tableId) async {
    _bleService.assignWaiterLocally(tableId, '', '');
    if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
      await _dbService.removeWaiterFromTable(
        tableId,
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
    }
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
    await _dbService.deleteWaiter(waiterId, managerPhone: managerPhone);
  }

  Future<void> acceptTableRequest({
    required String tableId,
    required String waiterName,
    String? waiterId,
  }) async {
    NotificationAudioService().stop();
    _pendingEntryTimestamps.remove(tableId);
    _escalatedTableIds.remove(tableId);
    _clearNotifiedPending(tableId);
    final cleanDigits = tableId.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanDigits.isNotEmpty) {
      _pendingEntryTimestamps.remove('table_$cleanDigits');
      _pendingEntryTimestamps.remove(cleanDigits);
      _escalatedTableIds.remove('table_$cleanDigits');
      _escalatedTableIds.remove(cleanDigits);
      _clearNotifiedPending(cleanDigits);
      _clearNotifiedPending('table_$cleanDigits');
    }
    try {
      final notifId = int.tryParse(cleanDigits) ?? (tableId.hashCode & 0x7FFFFFFF);
      FCMService().clearNativeNotification(notifId);
    } catch (_) {}

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
    NotificationAudioService().stop();
    _pendingEntryTimestamps.remove(tableId);
    _escalatedTableIds.remove(tableId);
    _clearNotifiedPending(tableId);
    final cleanDigits = tableId.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanDigits.isNotEmpty) {
      _pendingEntryTimestamps.remove('table_$cleanDigits');
      _pendingEntryTimestamps.remove(cleanDigits);
      _escalatedTableIds.remove('table_$cleanDigits');
      _escalatedTableIds.remove(cleanDigits);
      _clearNotifiedPending(cleanDigits);
      _clearNotifiedPending('table_$cleanDigits');
    }
    try {
      final notifId = int.tryParse(cleanDigits) ?? (tableId.hashCode & 0x7FFFFFFF);
      FCMService().clearNativeNotification(notifId);
    } catch (_) {}

    await _dbService.resetTableStatus(tableId, managerPhone: managerPhone);
    await _bleService.resetTableStatus(tableId);
  }

  Future<void> resetAllTables() async {
    NotificationAudioService().stop();
    _notifiedPendingTableKeys.clear();
    _lastNotifiedRequestSentAt.clear();
    await _dbService.resetAllTables(managerPhone: managerPhone);
    await _bleService.resetAllTables();
  }

  Future<void> triggerTableRequest(
    String tableId, {
    dynamic tableNumber,
  }) async {
    _clearNotifiedPending(tableId, tableNumber);
    await _dbService.triggerTableRequest(
      tableId,
      tableNumber: tableNumber,
      managerPhone: managerPhone,
      managerUid: managerUid,
      managerEmail: managerEmail,
    );
    await _bleService.triggerTableRequest(tableId, tableNumber: tableNumber);
  }

  /// Verify Device Ownership: Validates both Device ID and Password against
  /// actual configured data sources (Firebase Realtime Database & Gateway hardware).
  /// If valid, admits device into the system and marks it authorized.
  Future<bool> verifyDeviceOwnership({
    required String deviceId,
    required String password,
  }) async {
    final cleanInput = deviceId.trim();
    final trimmedPassword = password.trim();

    if (cleanInput.isEmpty) {
      throw Exception('Device ID / Table Number cannot be empty.');
    }
    if (trimmedPassword.isEmpty) {
      throw Exception('Password cannot be empty.');
    }

    final cleanId = _bleService.cleanTableNum(cleanInput);
    final cleanDigits = cleanInput.replaceAll(RegExp(r'[^0-9]'), '');
    final tableId = 'table_$cleanId';

    // ------------------------------------------------------------------
    // Step 2: Fetch Device Details from actual configured data source
    // ------------------------------------------------------------------
    Map<String, dynamic>? registeredRecord;
    try {
      registeredRecord = await _dbService.fetchRegisteredTable(
        cleanInput,
        managerPhone: managerPhone,
      );
    } catch (e) {
      debugPrint('[AUTH] Cloud table lookup note: $e');
    }

    // Also check if device is registered/known in the Wi-Fi Gateway live device registry
    final liveTable = _bleService.getLiveTable(cleanId) ??
        (cleanDigits.isNotEmpty ? _bleService.getLiveTable(cleanDigits) : null);
    final isKnownOnGateway = liveTable != null || _bleService.isDeviceRegistered(cleanId);

    // If device does not exist in any configured data source
    if (registeredRecord == null && !isKnownOnGateway) {
      if (_bleService.devicePasswordValidator == null) {
        throw Exception(
          'Device / Table "$cleanInput" is not registered in the system. Please configure the table first.',
        );
      }
    }

    // ------------------------------------------------------------------
    // Step 3: Compare Credentials & Validate Authentication
    // ------------------------------------------------------------------
    if (registeredRecord != null) {
      final storedCredential = (registeredRecord['device_password'] ??
              registeredRecord['password'])
          ?.toString()
          .trim();

      if (storedCredential != null &&
          storedCredential.isNotEmpty &&
          storedCredential != trimmedPassword) {
        throw Exception(
          'Authentication failed for Table/Device "$cleanInput": Incorrect password.',
        );
      }
    }

    // Challenge the physical device / Gateway via AUTH command
    final verified = await _bleService.verifyDeviceOwnership(
      deviceId: cleanId,
      password: trimmedPassword,
      managerPhone: managerPhone,
      managerUid: managerUid,
    );

    // ------------------------------------------------------------------
    // Step 4 & 5: Process Authentication Result
    // ------------------------------------------------------------------
    if (!verified) {
      throw Exception(
        'Authentication failed for Table/Device "$cleanInput": Invalid password. Access rejected.',
      );
    }

    _bleService.authorizeTableForManager(
      tableId: cleanId,
      password: trimmedPassword,
      managerPhone: managerPhone,
      managerUid: managerUid,
    );

    // Persist verified credential dynamically in local secure store
    if (_credentialService != null) {
      await _credentialService.saveCredential(
        cleanId,
        trimmedPassword,
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
      if (cleanDigits.isNotEmpty && cleanDigits != cleanId) {
        await _credentialService.saveCredential(
          cleanDigits,
          trimmedPassword,
          managerPhone: managerPhone,
          managerUid: managerUid,
        );
      }
    }

    // Mark table as unlocked in Firebase Realtime Database
    if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
      await _dbService.unlockTable(
        tableId,
        managerPhone: managerPhone,
        managerUid: managerUid,
        password: trimmedPassword,
      );
      if (cleanDigits.isNotEmpty && 'table_$cleanDigits' != tableId) {
        await _dbService.unlockTable(
          'table_$cleanDigits',
          managerPhone: managerPhone,
          managerUid: managerUid,
          password: trimmedPassword,
        );
      }
    }

    return true;
  }

  // Authorize & Unlock a Table with Device Password (Manager Only)
  Future<bool> verifyAndUnlockTable({
    required String tableId,
    required String password,
  }) async {
    return verifyDeviceOwnership(
      deviceId: tableId,
      password: password,
    );
  }

  // Lock a Table (Manager Only)
  Future<void> lockTable(String tableId) async {
    final cleanDigits = tableId.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanId = _bleService.cleanTableNum(tableId);

    // Deauthorize for THIS manager in GatewayWifiService
    _bleService.deauthorizeTableForManager(
      tableId: tableId,
      managerPhone: managerPhone,
      managerUid: managerUid,
    );
    if (cleanDigits.isNotEmpty && 'table_$cleanDigits' != tableId) {
      _bleService.deauthorizeTableForManager(
        tableId: 'table_$cleanDigits',
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
    }
    _bleService.deauthorizeTableForManager(
      tableId: cleanId,
      managerPhone: managerPhone,
      managerUid: managerUid,
    );

    if (managerPhone.isNotEmpty || managerUid.isNotEmpty) {
      await _dbService.lockTable(
        tableId,
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
      if (cleanDigits.isNotEmpty && 'table_$cleanDigits' != tableId) {
        await _dbService.lockTable(
          'table_$cleanDigits',
          managerPhone: managerPhone,
          managerUid: managerUid,
        );
      }
    }
    await _bleService.lockTableLocally(
      tableId,
      managerPhone: managerPhone,
      managerUid: managerUid,
    );
    if (cleanDigits.isNotEmpty && 'table_$cleanDigits' != tableId) {
      await _bleService.lockTableLocally(
        'table_$cleanDigits',
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
    }
    if (_credentialService != null) {
      await _credentialService.removeCredential(
        cleanId,
        managerPhone: managerPhone,
        managerUid: managerUid,
      );
      if (cleanDigits.isNotEmpty && cleanDigits != cleanId) {
        await _credentialService.removeCredential(
          cleanDigits,
          managerPhone: managerPhone,
          managerUid: managerUid,
        );
      }
    }
  }

  void dispose() {
    _cloudRequestSub?.cancel();
    _managerEscalationTicker?.cancel();
  }
}
