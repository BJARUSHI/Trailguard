import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../constants/app_constants.dart';
import '../models/safety_prediction.dart';
import 'hiking_session_service.dart';

/// Module 8: Alert System — visual, sound, and vibration alerts
class AlertService {
  static final AlertService instance = AlertService._();
  AlertService._();

  final _notifications = FlutterLocalNotificationsPlugin();
  final _sessionService = HikingSessionService.instance;

  StreamSubscription<SafetyPrediction>? _predSub;
  DateTime? _disorientedSince;
  bool _emergencyTriggered = false;

  // Callbacks for UI layer
  Function(SafetyPrediction)? onAlert;
  VoidCallback? onEmergency;

  // ── Initialization ───────────────────────────────────────────
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            AppConstants.channelId,
            AppConstants.channelName,
            importance: Importance.high,
            enableVibration: true,
            playSound: true,
          ),
        );

    // Separate channel for stillness/immobility alerts — max importance,
    // full-screen intent, its own sound (distinct from the routine GPS
    // channel above) so it's impossible to miss even if the app isn't in
    // the foreground.
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            AppConstants.stillnessChannelId,
            AppConstants.stillnessChannelName,
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        );
  }

  Future<void> showStillnessAlertNotification() async {
    await _notifications.show(
      AppConstants.stillnessNotificationId,
      '🆘 Are you okay?',
      'No movement detected for ${AppConstants.stillnessAlertThresholdSeconds} seconds. '
          'Open TrailGuard to respond.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.stillnessChannelId,
          AppConstants.stillnessChannelName,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          enableVibration: true,
          playSound: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          category: AndroidNotificationCategory.alarm,
          color: Color(0xFFFF3D3D),
        ),
      ),
    );
  }

  Future<void> cancelStillnessAlertNotification() async {
    await _notifications.cancel(AppConstants.stillnessNotificationId);
  }

  // ── Start / Stop ─────────────────────────────────────────────
  void startMonitoring() {
    _disorientedSince = null;
    _emergencyTriggered = false;
    _predSub = _sessionService.predictionStream.listen(_handlePrediction);
  }

  void stopMonitoring() {
    _predSub?.cancel();
    _predSub = null;
    _disorientedSince = null;
    _emergencyTriggered = false;
    cancelAlerts();
  }

  // ── Handler ──────────────────────────────────────────────────
  void _handlePrediction(SafetyPrediction pred) {
    onAlert?.call(pred);
    if (pred.riskLevel == RiskLevel.disoriented) {
      _disorientedSince ??= DateTime.now();
      _sendAlert(
        title: '⚠️ TrailGuard Alert',
        body: 'Possible Disorientation Detected — Confidence: ${pred.confidenceScore}%',
        color: const Color(0xFFFF3D3D),
        importance: Importance.max,
        priority: Priority.high,
      );
      _checkEmergencyEscalation();
    } else if (pred.riskLevel == RiskLevel.caution) {
      _disorientedSince = null;
      _sendAlert(
        title: '🟡 TrailGuard Caution',
        body: 'Movement patterns suggest reduced navigation confidence',
        color: const Color(0xFFF0883E),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
    } else {
      _disorientedSince = null;
    }
  }

  void _sendAlert({
    required String title,
    required String body,
    required Color color,
    required Importance importance,
    required Priority priority,
  }) {
    _notifications.show(
      AppConstants.alertNotificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.channelId,
          AppConstants.channelName,
          importance: importance,
          priority: priority,
          enableVibration: true,
          playSound: true,
          icon: '@mipmap/ic_launcher',
          color: color,
        ),
      ),
    );
  }

  void _checkEmergencyEscalation() {
    if (_emergencyTriggered || _disorientedSince == null) return;
    final elapsed = DateTime.now().difference(_disorientedSince!);
    if (elapsed.inMinutes >= AppConstants.emergencyActivationMinutes) {
      _emergencyTriggered = true;
      _activateEmergencyMode();
    }
  }

  Future<void> _activateEmergencyMode() async {
    await _sessionService.logEmergency(
      'Emergency auto-activated: hiker disoriented for '
      '${AppConstants.emergencyActivationMinutes} minutes',
    );
    _notifications.show(
      AppConstants.alertNotificationId + 1,
      '🆘 EMERGENCY MODE ACTIVATED',
      'Hiker disoriented for ${AppConstants.emergencyActivationMinutes} min. '
          'Emergency report saved. Return-to-safety route available.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.channelId,
          AppConstants.channelName,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          enableVibration: true,
          playSound: true,
          color: Color(0xFFFF0000),
        ),
      ),
    );
    onEmergency?.call();
  }

  void cancelAlerts() {
    _notifications.cancel(AppConstants.alertNotificationId);
  }
}
