import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared_preferences_provider.dart';

/// Dynamic, device-specific credential storage for Tab2Notify.
/// Manages dynamically verified table & device credentials across sessions
/// without hardcoding any passwords or device lists.
class DeviceCredentialService {
  final SharedPreferences? _prefs;
  final Map<String, String> _inMemoryFallback = {};

  DeviceCredentialService([this._prefs]);

  String _storageKey(String? managerPhone) {
    final cleanPhone = (managerPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return 't2n_device_creds_${cleanPhone.isNotEmpty ? cleanPhone : "default"}';
  }

  /// Retrieve all dynamically stored credentials for the manager session
  Map<String, String> getAllCredentials({String? managerPhone}) {
    if (_prefs == null) {
      return Map.unmodifiable(_inMemoryFallback);
    }
    final raw = _prefs.getString(_storageKey(managerPhone));
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
  String? getCredential(String deviceId, {String? managerPhone}) {
    final clean = _cleanId(deviceId);
    final all = getAllCredentials(managerPhone: managerPhone);
    return all[clean];
  }

  /// Persist verified credential dynamically
  Future<void> saveCredential(
    String deviceId,
    String password, {
    String? managerPhone,
  }) async {
    final clean = _cleanId(deviceId);
    final trimmedPass = password.trim();
    if (clean.isEmpty || trimmedPass.isEmpty) return;

    if (_prefs == null) {
      _inMemoryFallback[clean] = trimmedPass;
      return;
    }

    final all = getAllCredentials(managerPhone: managerPhone);
    final updated = Map<String, String>.from(all);
    updated[clean] = trimmedPass;

    await _prefs.setString(_storageKey(managerPhone), jsonEncode(updated));
  }

  /// Remove credential on lock / revocation
  Future<void> removeCredential(
    String deviceId, {
    String? managerPhone,
  }) async {
    final clean = _cleanId(deviceId);
    if (_prefs == null) {
      _inMemoryFallback.remove(clean);
      return;
    }

    final all = getAllCredentials(managerPhone: managerPhone);
    if (!all.containsKey(clean)) return;

    final updated = Map<String, String>.from(all);
    updated.remove(clean);
    await _prefs.setString(_storageKey(managerPhone), jsonEncode(updated));
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
