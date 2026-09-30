import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/gps_point.dart';
import '../../core/models/behavioral_features.dart';
import '../../core/models/safety_prediction.dart';
import '../../core/services/gps_tracking_service.dart';
import '../../core/services/hiking_session_service.dart';
import '../../core/services/alert_service.dart';
import '../sessions/start_session_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final _sessionService = HikingSessionService.instance;
  final _gps = GpsTrackingService.instance;
  final _alert = AlertService.instance;

  StreamSubscription<GpsPoint>? _gpsSub;
  StreamSubscription<SafetyPrediction>? _predSub;
  StreamSubscription<BehavioralFeatures>? _featSub;
  StreamSubscription<bool>? _pauseSub;

  GpsPoint? _lastGps;
  SafetyPrediction? _prediction;
  BehavioralFeatures? _features;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    if (_gps.lastPoint != null) {
      _lastGps = _gps.lastPoint;
    } else {
      _gps.getCurrentLocation("dashboard").then((loc) {
        if (mounted && _lastGps == null && loc != null) {
          setState(() => _lastGps = loc);
        }
      });
    }

    _gpsSub = _gps.positionStream.listen((p) {
      if (mounted) setState(() => _lastGps = p);
    });
    _predSub = _sessionService.predictionStream.listen((p) {
      if (mounted) setState(() => _prediction = p);
    });
    _featSub = _sessionService.featuresStream.listen((f) {
      if (mounted) setState(() => _features = f);
    });
    _pauseSub = _sessionService.pauseStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _predSub?.cancel();
    _featSub?.cancel();
    _pauseSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  bool get _isTracking => _sessionService.currentSession != null;

  Color get _riskColor {
    if (_sessionService.isPaused) return const Color(0xFFF0883E);
    final level = _prediction?.riskLevel ?? RiskLevel.safe;
    if (level == RiskLevel.disoriented) return const Color(0xFFFF3D3D);
    if (level == RiskLevel.caution) return const Color(0xFFF0883E);
    return const Color(0xFF3FB950);
  }

  String get _riskLabel {
    if (_sessionService.isPaused) return 'PAUSED';
    final level = _prediction?.riskLevel ?? RiskLevel.safe;
    if (level == RiskLevel.disoriented) return 'DISORIENTED';
    if (level == RiskLevel.caution) return 'CAUTION';
    return 'SAFE';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('assets/icon.png', height: 24, errorBuilder: (_, __, ___) =>
              const Icon(Icons.terrain, color: Color(0xFF3FB950), size: 24)),
          const SizedBox(width: 10),
          const Text('TrailGuard'),
        ]),
        actions: [
          if (_isTracking)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF3FB950),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3FB950)
                              .withValues(alpha: _pulse.value * 0.8),
                          blurRadius: 8,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status Banner ──────────────────────────────────
            _StatusBanner(
              isTracking: _isTracking,
              riskColor: _riskColor,
              riskLabel: _riskLabel,
              sessionName: _sessionService.currentSession?.name,
            ),
            const SizedBox(height: 16),

            // ── Confidence Score ───────────────────────────────
            _ConfidenceCard(
              score: _prediction?.confidenceScore ?? 95,
              probability: _prediction?.disorientationProbability ?? 0.0,
              riskColor: _riskColor,
              isTracking: _isTracking,
            ),
            const SizedBox(height: 12),

            // ── GPS Info ───────────────────────────────────────
            _GpsInfoCard(point: _lastGps),
            const SizedBox(height: 12),

            // ── Behavioral Features ────────────────────────────
            if (_features != null) ...[
              _FeaturesCard(features: _features!),
              const SizedBox(height: 12),
            ],

            // ── Action Buttons ─────────────────────────────────
            _ActionButtons(
              isTracking: _isTracking,
              onStart: _startSession,
              onStop: _stopSession,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _startSession() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const StartSessionDialog(),
    );
    if (result == null) return;

    final hasPermission = await _gps.requestPermissions();
    if (!hasPermission && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission required')),
      );
      return;
    }

    await _sessionService.startSession(
      name: result['name'] as String,
      destLat: result['destLat'] as double?,
      destLon: result['destLon'] as double?,
    );
    _alert.startMonitoring();

    if (mounted) setState(() {});
  }

  Future<void> _stopSession() async {
    _alert.stopMonitoring();
    await _sessionService.endSession();
    setState(() {
      _lastGps = null;
      _prediction = null;
      _features = null;
    });
  }
}

// ─── Status Banner ────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final bool isTracking;
  final Color riskColor;
  final String riskLabel;
  final String? sessionName;

  const _StatusBanner({
    required this.isTracking,
    required this.riskColor,
    required this.riskLabel,
    this.sessionName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isTracking
            ? riskColor.withValues(alpha: 0.12)
            : const Color(0xFF1C2128),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTracking ? riskColor.withValues(alpha: 0.4) : Colors.transparent,
        ),
      ),
      child: Row(children: [
        Icon(
          isTracking ? Icons.shield : Icons.shield_outlined,
          color: isTracking ? riskColor : const Color(0xFF8B949E),
          size: 32,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isTracking ? riskLabel : 'NOT TRACKING',
              style: TextStyle(
                color: isTracking ? riskColor : const Color(0xFF8B949E),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            if (sessionName != null)
              Text(
                sessionName!,
                style: const TextStyle(
                    color: Color(0xFF8B949E), fontSize: 13),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Confidence Score Card ────────────────────────────────────
class _ConfidenceCard extends StatelessWidget {
  final int score;
  final double probability;
  final Color riskColor;
  final bool isTracking;

  const _ConfidenceCard({
    required this.score,
    required this.probability,
    required this.riskColor,
    required this.isTracking,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('NAVIGATION CONFIDENCE',
              style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 11,
                  letterSpacing: 1.2)),
          const SizedBox(height: 16),
          Row(children: [
            // Score ring
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: isTracking ? score / 100 : 0,
                    strokeWidth: 7,
                    backgroundColor: const Color(0xFF30363D),
                    valueColor: AlwaysStoppedAnimation(riskColor),
                  ),
                ),
                Text(
                  isTracking ? '$score' : '--',
                  style: TextStyle(
                      color: riskColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w800),
                ),
              ]),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetricRow(
                      label: 'Disorientation Risk',
                      value: isTracking
                          ? '${(probability * 100).toStringAsFixed(0)}%'
                          : '--',
                      color: isTracking
                          ? Color.lerp(
                              const Color(0xFF3FB950),
                              const Color(0xFFFF3D3D),
                              probability)!
                          : const Color(0xFF8B949E),
                    ),
                    const SizedBox(height: 8),
                    _MetricRow(
                      label: 'Score Band',
                      value: isTracking
                          ? (score <= AppConstants.highRiskMax
                              ? 'High Risk'
                              : score <= AppConstants.moderateRiskMax
                                  ? 'Moderate'
                                  : 'Stable')
                          : '--',
                      color: const Color(0xFF8B949E),
                    ),
                  ]),
            )
          ]),
        ]),
      ),
    );
  }
}

// ─── GPS Info Card ────────────────────────────────────────────
class _GpsInfoCard extends StatelessWidget {
  final GpsPoint? point;
  const _GpsInfoCard({this.point});

  @override
  Widget build(BuildContext context) {
    final p = point;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GPS STATUS',
              style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 11,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _GpsCell(
                    label: 'Latitude',
                    value: p != null
                        ? p.latitude.toStringAsFixed(5)
                        : '--',
                    icon: Icons.my_location)),
            Expanded(
                child: _GpsCell(
                    label: 'Longitude',
                    value: p != null
                        ? p.longitude.toStringAsFixed(5)
                        : '--',
                    icon: Icons.location_on)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _GpsCell(
                    label: 'Altitude',
                    value:
                        p != null ? '${p.altitude.toStringAsFixed(1)}m' : '--',
                    icon: Icons.terrain)),
            Expanded(
                child: _GpsCell(
                    label: 'Speed',
                    value: p != null
                        ? '${(p.speed * 3.6).toStringAsFixed(1)} km/h'
                        : '--',
                    icon: Icons.speed)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _GpsCell(
                    label: 'Bearing',
                    value:
                        p != null ? '${p.bearing.toStringAsFixed(0)}°' : '--',
                    icon: Icons.explore)),
            Expanded(
                child: _GpsCell(
                    label: 'Accuracy',
                    value:
                        p != null ? '±${p.accuracy.toStringAsFixed(0)}m' : '--',
                    icon: Icons.gps_fixed)),
          ]),
        ]),
      ),
    );
  }
}

class _GpsCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _GpsCell({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: const Color(0xFF8B949E)),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style:
                const TextStyle(color: Color(0xFF8B949E), fontSize: 10)),
        Text(value,
            style: const TextStyle(
                color: Color(0xFFE6EDF3),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ]),
    ]);
  }
}

// ─── Features Card ────────────────────────────────────────────
class _FeaturesCard extends StatelessWidget {
  final BehavioralFeatures features;
  const _FeaturesCard({required this.features});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('BEHAVIORAL ANALYSIS',
              style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 11,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          _FeatureBar(
              label: 'Path Efficiency',
              value: features.pathEfficiency,
              good: true),
          _FeatureBar(
              label: 'Direction Stability',
              value: 1 - features.directionVariance,
              good: true),
          _FeatureBar(
              label: 'Speed Stability',
              value: features.speedStability,
              good: true),
          _FeatureBar(
              label: 'Backtracking',
              value: features.backtrackingRatio,
              good: false),
          _FeatureBar(
              label: 'Loop Detection',
              value: features.loopScore,
              good: false),
          _FeatureBar(
              label: 'Movement Entropy',
              value: features.movementEntropy,
              good: false),
        ]),
      ),
    );
  }
}

class _FeatureBar extends StatelessWidget {
  final String label;
  final double value;
  final bool good; // true=high is good, false=high is bad

  const _FeatureBar({
    required this.label,
    required this.value,
    required this.good,
  });

  Color get _color {
    final v = good ? value : 1 - value;
    if (v > 0.65) return const Color(0xFF3FB950);
    if (v > 0.35) return const Color(0xFFF0883E);
    return const Color(0xFFFF3D3D);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFF8B949E), fontSize: 12)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: const Color(0xFF30363D),
              valueColor: AlwaysStoppedAnimation(_color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '${(value * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
                color: _color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

// ─── Action Buttons ───────────────────────────────────────────
class _ActionButtons extends StatelessWidget {
  final bool isTracking;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _ActionButtons({
    required this.isTracking,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final sessionService = HikingSessionService.instance;
    final isPaused = sessionService.isPaused;

    return Row(children: [
      if (isTracking) ...[
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              if (isPaused) {
                sessionService.resumeSession();
              } else {
                sessionService.pauseSession();
              }
            },
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
            label: Text(isPaused ? 'Resume' : 'Pause'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isPaused ? const Color(0xFF3FB950) : const Color(0xFFF0883E),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined,
                color: Color(0xFFFF3D3D)),
            label: const Text('End Hike',
                style: TextStyle(color: Color(0xFFFF3D3D))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFF3D3D)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ] else
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Hike'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
    ]);
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricRow(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF8B949E), fontSize: 12)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]);
  }
}
