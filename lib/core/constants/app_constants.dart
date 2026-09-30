class AppConstants {
  // GPS Tracking
  static const int gpsIntervalSeconds = 5;
  static const double minDistanceMeters = 3.0;
  static const int trajectoryBufferSize = 500;

  // ML Thresholds
  static const double disorientationThreshold = 0.70;
  static const double cautionThreshold = 0.45;
  static const int minPointsForAnalysis = 10;

  // Confidence Score Bands
  static const int highRiskMax = 30;
  static const int moderateRiskMax = 60;

  // Feature Extraction
  static const int featureWindowSize = 20; // last N points
  static const double backtrackAngleThreshold = 150.0; // degrees
  static const double loopDetectionRadiusMeters = 30.0;

  // Alert Timings
  static const int persistentDisorientationMinutes = 5;
  static const int emergencyActivationMinutes = 10;

  // Database
  static const String dbName = 'trailguard.db';
  static const int dbVersion = 1;

  // Notification
  static const String channelId = 'trailguard_gps';
  static const String channelName = 'TrailGuard GPS Tracking';
  static const int notificationId = 1001;
  static const int alertNotificationId = 1002;

  // Terrain
  static const double flatTerrainSlopeDeg = 5.0;
  static const double steepTerrainSlopeDeg = 20.0;

  // Dead Reckoning
  static const int gpsLossTimeoutSeconds = 15;

  // Stillness / Immobility Detection
  static const double stillnessRadiusMeters = 10.0;
  static const int stillnessAlertThresholdSeconds = 60;
  static const int stillnessCountdownSeconds = 20;
  static const String stillnessAlertEnabledPrefKey = 'stillness_alert_enabled';
  static const String stillnessChannelId = 'trailguard_stillness';
  static const String stillnessChannelName = 'TrailGuard Stillness Alerts';
  static const int stillnessNotificationId = 2001;
}

class RiskLevel {
  static const String safe = 'SAFE';
  static const String caution = 'CAUTION';
  static const String disoriented = 'DISORIENTED';
}

class TableNames {
  static const String sessions = 'sessions';
  static const String gpsPoints = 'gps_points';
  static const String features = 'features';
  static const String predictions = 'predictions';
  static const String safeZones = 'safe_zones';
  static const String emergencyLogs = 'emergency_logs';
  static const String offlineRegions = 'offline_regions';
  static const String offlineWaypoints = 'offline_waypoints';
}
