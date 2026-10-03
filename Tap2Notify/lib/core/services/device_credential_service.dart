import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared_preferences_provider.dart';

/// Dynamic, device-specific credential storage for Tap2Notify.
/// Manages dynamically verified table & device credentials across sessions
/// without hardcoding any passwords or device lists.
class DeviceCredentialService {
  final SharedPreferences? _prefs;
  final Map<String, Map<String, String>> _inMemoryFallback = {};

  DeviceCredentialService([this._prefs]);

  String _storageKey(String? managerPhone, [String? managerUid]) {
    final phone = (managerPhone ?? '').trim();
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 10) {
      return 't2n_device_creds_phone_${digits.substring(digits.length - 10)}';
    }
    if (digits.isNotEmpty && digits.length >= 7 && digits == phone) {
      return 't2n_device_creds_phone_$digits';
    }
    final uid = (managerUid ?? '').trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (uid.isNotEmpty) {
      return 't2n_device_creds_uid_$uid';
    }
    final cleanPhone = phone.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (cleanPhone.isNotEmpty) {
      return 't2n_device_creds_mgr_$cleanPhone';
    }
    return 't2n_device_creds_default';
  }

  /// Retrieve all dynamically stored credentials for the manager session
  Map<String, String> getAllCredentials({String? managerPhone, String? managerUid}) {
    final key = _storageKey(managerPhone, managerUid);
    if (_prefs == null) {
      return Map.unmodifiable(_inMemoryFallback[key] ?? {});
    }
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (e) {
      debugPrint('[DEVICE CREDS] Error reading credentials: $e');
    }
    return {};
  }

  /// Retrieve stored password for a specific device / table
  String? getCredential(
    String deviceId, {
    String? managerPhone,
    String? managerUid,
  }) {
    final clean = _cleanId(deviceId);
    final all = getAllCredentials(
      managerPhone: managerPhone,
      managerUid: managerUid,
    );
    return all[clean];
  }

  /// Persist verified credential dynamically
  Future<void> saveCredential(
    String deviceId,
    String password, {
    String? managerPhone,
    String? managerUid,
  }) async {
    final clean = _cleanId(deviceId);
    final trimmedPass = password.trim();
    if (clean.isEmpty || trimmedPass.isEmpty) return;
    final key = _storageKey(managerPhone, managerUid);

    if (_prefs == null) {
      final map = _inMemoryFallback.putIfAbsent(key, () => <String, String>{});
      map[clean] = trimmedPass;
      return;
    }

    final all = getAllCredentials(
      managerPhone: managerPhone,
      managerUid: managerUid,
    );
    final updated = Map<String, String>.from(all);
    updated[clean] = trimmedPass;

    await _prefs.setString(key, jsonEncode(updated));
  }

  /// Remove credential on lock / revocation
  Future<void> removeCredential(
    String deviceId, {
    String? managerPhone,
    String? managerUid,
  }) async {
    final clean = _cleanId(deviceId);
    final key = _storageKey(managerPhone, managerUid);
    if (_prefs == null) {
      _inMemoryFallback[key]?.remove(clean);
      return;
    }

    final all = getAllCredentials(
      managerPhone: managerPhone,
      managerUid: managerUid,
    );
    if (!all.containsKey(clean)) return;

    final updated = Map<String, String>.from(all);
    updated.remove(clean);
    await _prefs.setString(key, jsonEncode(updated));
  }

  /// Normalize device/table identifier
  static String _cleanId(String id) {
    String s = id.trim();
    if (s.startsWith('table_')) {
      s = s.substring(6);
    } else if (s.startsWith('device_')) {
      s = s.substring(7);
    }
    return s;
  }
}

final deviceCredentialServiceProvider = Provider<DeviceCredentialService>((ref) {
  try {
    final prefs = ref.watch(sharedPreferencesProvider);
    return DeviceCredentialService(prefs);
  } catch (_) {
    return DeviceCredentialService();
  }
});
