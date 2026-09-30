class BehavioralFeatures {
  final String sessionId;
  final DateTime timestamp;

  // Movement features
  final double directionVariance;    // 0–1: higher = more chaotic direction changes
  final double backtrackingRatio;    // 0–1: proportion of reversals
  final double pathEfficiency;       // 0–1: straight-line / actual distance
  final double loopScore;            // 0–1: circular movement detected
  final double movementEntropy;      // 0–1: randomness of movement
  final double speedStability;       // 0–1: inverse of speed variance
  final double stopFrequency;        // 0–1: stops per unit time

  // Terrain features
  final double elevationChange;      // meters
  final double terrainSlope;         // degrees

  // Progress
  final double progressTowardDest;   // 0–1: moving toward destination

  const BehavioralFeatures({
    required this.sessionId,
    required this.timestamp,
    this.directionVariance = 0.0,
    this.backtrackingRatio = 0.0,
    this.pathEfficiency = 1.0,
    this.loopScore = 0.0,
    this.movementEntropy = 0.0,
    this.speedStability = 1.0,
    this.stopFrequency = 0.0,
    this.elevationChange = 0.0,
    this.terrainSlope = 0.0,
    this.progressTowardDest = 1.0,
  });

  /// Feature vector for ML model (same order as training)
  List<double> toFeatureVector() => [
        directionVariance,
        backtrackingRatio,
        pathEfficiency,
        loopScore,
        movementEntropy,
        speedStability,
        stopFrequency,
        elevationChange,
        terrainSlope,
      ];

  factory BehavioralFeatures.fromMap(Map<String, dynamic> map) {
    return BehavioralFeatures(
      sessionId: map['session_id'] as String,
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      directionVariance:
          (map['direction_variance'] as num?)?.toDouble() ?? 0.0,
      backtrackingRatio:
          (map['backtracking_ratio'] as num?)?.toDouble() ?? 0.0,
      pathEfficiency:
          (map['path_efficiency'] as num?)?.toDouble() ?? 1.0,
      loopScore: (map['loop_score'] as num?)?.toDouble() ?? 0.0,
      movementEntropy:
          (map['movement_entropy'] as num?)?.toDouble() ?? 0.0,
      speedStability:
          (map['speed_stability'] as num?)?.toDouble() ?? 1.0,
      stopFrequency:
          (map['stop_frequency'] as num?)?.toDouble() ?? 0.0,
      elevationChange:
          (map['elevation_change'] as num?)?.toDouble() ?? 0.0,
      terrainSlope:
          (map['terrain_slope'] as num?)?.toDouble() ?? 0.0,
      progressTowardDest:
          (map['progress_toward_dest'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'session_id': sessionId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'direction_variance': directionVariance,
      'backtracking_ratio': backtrackingRatio,
      'path_efficiency': pathEfficiency,
      'loop_score': loopScore,
      'movement_entropy': movementEntropy,
      'speed_stability': speedStability,
      'stop_frequency': stopFrequency,
      'elevation_change': elevationChange,
      'terrain_slope': terrainSlope,
      'progress_toward_dest': progressTowardDest,
    };
  }

  @override
  String toString() =>
      'Features(eff:${pathEfficiency.toStringAsFixed(2)}, '
      'backtrack:${backtrackingRatio.toStringAsFixed(2)}, '
      'entropy:${movementEntropy.toStringAsFixed(2)})';
}
