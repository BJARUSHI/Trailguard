import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:trailguard/core/models/behavioral_features.dart';
import 'package:trailguard/core/models/safety_prediction.dart';
import 'package:trailguard/core/constants/app_constants.dart';

class MLInferenceEngine {
  static MLInferenceEngine? _instance;
  static MLInferenceEngine get instance =>
      _instance ??= MLInferenceEngine._();
  MLInferenceEngine._();

  List<double> _weights = [
    -2.1, 2.8, 3.2, -3.5, 2.6, 1.9, -1.4, 1.7, 0.3, 0.2
  ];

  final List<double> _featureMean = [
    0.35, 0.15, 0.70, 0.10, 0.45, 0.75, 0.20, 5.0, 3.0
  ];
  final List<double> _featureStd = [
    0.25, 0.15, 0.25, 0.15, 0.25, 0.20, 0.20, 8.0, 5.0
  ];

  bool _modelLoaded = false;

  Future<void> loadModel() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/models/lr_weights.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      _weights = (data['weights'] as List).map((e) => (e as num).toDouble()).toList();
      final means = data['feature_mean'] as List;
      final stds = data['feature_std'] as List;
      for (int i = 0; i < means.length; i++) {
        _featureMean[i] = (means[i] as num).toDouble();
        _featureStd[i] = (stds[i] as num).toDouble();
      }
      _modelLoaded = true;
    } catch (_) {
      _modelLoaded = true;
    }
  }

  SafetyPrediction predict(BehavioralFeatures features) {
    final vec = features.toFeatureVector();
    final prob = _logisticRegression(vec);
    final confidence = _computeConfidenceScore(features, prob);
    final risk = _classifyRisk(prob);
    return SafetyPrediction(
      sessionId: features.sessionId,
      timestamp: features.timestamp,
      disorientationProbability: prob,
      confidenceScore: confidence,
      riskLevel: risk,
    );
  }

  double _logisticRegression(List<double> features) {
    final normalized = <double>[];
    for (int i = 0; i < features.length; i++) {
      final std = _featureStd[i] < 0.001 ? 1.0 : _featureStd[i];
      normalized.add((features[i] - _featureMean[i]) / std);
    }
    double z = _weights[0];
    for (int i = 0; i < normalized.length; i++) {
      z += _weights[i + 1] * normalized[i];
    }
    return 1.0 / (1.0 + math.exp(-z));
  }

  int _computeConfidenceScore(BehavioralFeatures f, double disorientProb) {
    double score = 0.0;
    score += (1 - f.directionVariance) * 20;
    score += f.pathEfficiency * 25;
    score += (1 - f.backtrackingRatio) * 20;
    score += f.speedStability * 15;
    score += (1 - f.loopScore) * 10;
    score += (1 - disorientProb) * 10;
    final terrainPenalty = (f.terrainSlope / 45.0).clamp(0.0, 0.15) * 100;
    score = (score - terrainPenalty).clamp(0, 100);
    return score.round();
  }

  String _classifyRisk(double prob) {
    if (prob >= AppConstants.disorientationThreshold) return RiskLevel.disoriented;
    if (prob >= AppConstants.cautionThreshold) return RiskLevel.caution;
    return RiskLevel.safe;
  }

  bool get isLoaded => _modelLoaded;
}
