import '../constants/app_constants.dart';

class SafetyPrediction {
  final String sessionId;
  final DateTime timestamp;
  final double disorientationProbability; // 0.0 – 1.0
  final int confidenceScore;              // 0 – 100
  final String riskLevel;                 // SAFE / CAUTION / DISORIENTED

  const SafetyPrediction({
    required this.sessionId,
    required this.timestamp,
    required this.disorientationProbability,
    required this.confidenceScore,
    required this.riskLevel,
  });

  bool get isEmergency =>
      disorientationProbability >= AppConstants.disorientationThreshold;

  bool get isCaution =>
      disorientationProbability >= AppConstants.cautionThreshold &&
      !isEmergency;

  factory SafetyPrediction.safe(String sessionId) {
    return SafetyPrediction(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      disorientationProbability: 0.0,
      confidenceScore: 95,
      riskLevel: RiskLevel.safe,
    );
  }

  factory SafetyPrediction.fromMap(Map<String, dynamic> map) {
    return SafetyPrediction(
      sessionId: map['session_id'] as String,
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      disorientationProbability:
          (map['disorientation_probability'] as num).toDouble(),
      confidenceScore: map['confidence_score'] as int,
      riskLevel: map['risk_level'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'session_id': sessionId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'disorientation_probability': disorientationProbability,
      'confidence_score': confidenceScore,
      'risk_level': riskLevel,
    };
  }

  @override
  String toString() =>
      'Prediction(risk:$riskLevel, prob:${disorientationProbability.toStringAsFixed(2)}, '
      'conf:$confidenceScore)';
}
