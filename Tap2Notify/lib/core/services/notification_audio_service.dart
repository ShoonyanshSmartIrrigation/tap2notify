import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotificationAudioService {
  static final NotificationAudioService _instance = NotificationAudioService._internal();
  factory NotificationAudioService() => _instance;
  NotificationAudioService._internal();

  static const MethodChannel _nativeChannel =
      MethodChannel('tab2notify/native_notifications');

  int _lastPlayedTime = 0;
  String? _lastPlayedTableId;
  final Map<String, int> _lastPlayedTimes = {};

  int _lastManagerEscalationTime = 0;
  String? _lastManagerEscalationTableId;
  final Map<String, int> _lastManagerEscalationTimes = {};

  String _normalizeTableKey(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final numeric = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return numeric.isNotEmpty ? numeric : raw.trim().toLowerCase();
  }

  /// Plays the incoming request prompt audio asset (Incoming_Prompt.mp3)
  /// Debounces rapid successive calls for the same table within 8 seconds.
  Future<void> playIncomingRequestPrompt({String? tableId}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normKey = _normalizeTableKey(tableId);

    final lastPlayed = _lastPlayedTimes[normKey] ??
        (tableId != null ? _lastPlayedTimes[tableId] : null) ??
        0;

    if (normKey.isNotEmpty) {
      if (now - lastPlayed < 8000) {
        debugPrint('[AUDIO] Debounced duplicate prompt audio for $tableId (key: $normKey)');
        return;
      }
    } else {
      if (now - _lastPlayedTime < 8000) {
        debugPrint('[AUDIO] Debounced duplicate prompt audio (no tableId)');
        return;
      }
    }

    _lastPlayedTime = now;
    _lastPlayedTableId = normKey.isNotEmpty ? normKey : tableId;
    if (normKey.isNotEmpty) _lastPlayedTimes[normKey] = now;
    if (tableId != null) _lastPlayedTimes[tableId] = now;

    try {
      debugPrint('[AUDIO] Playing native incoming request prompt: R.raw.incoming_prompt (Table: $tableId)');
      await _nativeChannel.invokeMethod('playAudioPrompt');
    } catch (e) {
      debugPrint('[AUDIO ERROR] Failed to invoke native audio prompt: $e');
    }
  }

  /// Plays the manager escalation prompt audio asset (Please_Hold.mp3)
  /// Debounces rapid successive calls for the same table within 8 seconds.
  Future<void> playManagerEscalationPrompt({String? tableId}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normKey = _normalizeTableKey(tableId);

    final lastPlayed = _lastManagerEscalationTimes[normKey] ??
        (tableId != null ? _lastManagerEscalationTimes[tableId] : null) ??
        0;

    if (normKey.isNotEmpty) {
      if (now - lastPlayed < 8000) {
        debugPrint('[AUDIO] Debounced duplicate manager escalation audio for $tableId (key: $normKey)');
        return;
      }
    } else {
      if (now - _lastManagerEscalationTime < 8000) {
        debugPrint('[AUDIO] Debounced duplicate manager escalation audio (no tableId)');
        return;
      }
    }

    _lastManagerEscalationTime = now;
    _lastManagerEscalationTableId = normKey.isNotEmpty ? normKey : tableId;
    if (normKey.isNotEmpty) _lastManagerEscalationTimes[normKey] = now;
    if (tableId != null) _lastManagerEscalationTimes[tableId] = now;

    try {
      debugPrint('[AUDIO] Playing native manager escalation prompt: R.raw.please_hold (Table: $tableId)');
      await _nativeChannel.invokeMethod('playManagerAudioPrompt');
    } catch (e) {
      debugPrint('[AUDIO ERROR] Failed to invoke manager audio prompt: $e');
    }
  }

  /// For unit/integration tests to clear debounce state
  @visibleForTesting
  void resetForTesting() {
    _lastPlayedTime = 0;
    _lastPlayedTableId = null;
    _lastManagerEscalationTime = 0;
    _lastManagerEscalationTableId = null;
    _lastPlayedTimes.clear();
    _lastManagerEscalationTimes.clear();
  }

  /// Stop any active audio playback
  Future<void> stop() async {
    try {
      await _nativeChannel.invokeMethod('stopAudioPrompt');
    } catch (_) {}
  }

  void dispose() {
    stop();
  }
}
