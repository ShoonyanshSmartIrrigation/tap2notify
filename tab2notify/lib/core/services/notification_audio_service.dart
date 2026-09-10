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

  int _lastManagerEscalationTime = 0;
  String? _lastManagerEscalationTableId;

  /// Plays the incoming request prompt audio asset (Incoming_Prompt.mp3)
  /// Debounces rapid successive calls for the same table within 5 seconds.
  Future<void> playIncomingRequestPrompt({String? tableId}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (tableId != null &&
        tableId.isNotEmpty &&
        tableId == _lastPlayedTableId &&
        (now - _lastPlayedTime < 5000)) {
      debugPrint('[AUDIO] Debounced duplicate prompt audio for $tableId');
      return;
    }

    _lastPlayedTime = now;
    _lastPlayedTableId = tableId;

    try {
      debugPrint('[AUDIO] Playing native incoming request prompt: R.raw.incoming_prompt (Table: $tableId)');
      await _nativeChannel.invokeMethod('playAudioPrompt');
    } catch (e) {
      debugPrint('[AUDIO ERROR] Failed to invoke native audio prompt: $e');
    }
  }

  /// Plays the manager escalation prompt audio asset (Please_Hold.mp3)
  /// Debounces rapid successive calls for the same table within 5 seconds.
  Future<void> playManagerEscalationPrompt({String? tableId}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (tableId != null &&
        tableId.isNotEmpty &&
        tableId == _lastManagerEscalationTableId &&
        (now - _lastManagerEscalationTime < 5000)) {
      debugPrint('[AUDIO] Debounced duplicate manager escalation audio for $tableId');
      return;
    }

    _lastManagerEscalationTime = now;
    _lastManagerEscalationTableId = tableId;

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
