import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/models/safety_prediction.dart';
import '../../core/models/gps_point.dart';
import '../../core/services/hiking_session_service.dart';

/// Module 13: Analytics & Visualization
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final _sessionService = HikingSessionService.instance;
  late TabController _tabCtrl;

  List<SafetyPrediction> _predictions = [];
  List<GpsPoint> _trail = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadCurrentSession();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSession() async {
    final session = _sessionService.currentSession;
    if (session == null) return;
    setState(() => _loading = true);
    final preds = await _sessionService.getPredictionHistory(session.id);
    final trail = await _sessionService.getSessionTrail(session.id);
    if (mounted) {
      setState(() {
        _predictions = preds;
        _trail = trail;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadCurrentSession),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          indicatorColor: const Color(0xFF3FB950),
          labelColor: const Color(0xFF3FB950),
          unselectedLabelColor: const Color(0xFF8B949E),
          tabs: const [
            Tab(text: 'Confidence'),
            Tab(text: 'Speed'),
            Tab(text: 'Elevation'),
            Tab(text: 'Risk Trend'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessionService.currentSession == null
              ? _EmptyState(onRefresh: _loadCurrentSession)
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _ConfidenceChart(predictions: _predictions),
                    _SpeedChart(trail: _trail),
                    _ElevationChart(trail: _trail),
                    _RiskTrendChart(predictions: _predictions),
                  ],
                ),
    );
  }
}

// ─── Confidence Chart ─────────────────────────────────────────
class _ConfidenceChart extends StatelessWidget {
  final List<SafetyPrediction> predictions;
  const _ConfidenceChart({required this.predictions});

  @override
  Widget build(BuildContext context) {
    if (predictions.isEmpty) return const _NoDataPlaceholder();

    final spots = predictions.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.confidenceScore.toDouble());
    }).toList();

    return _ChartCard(
      title: 'Navigation Confidence Over Time',
      subtitle: 'Confidence score (0–100). Green = safe, Red = disoriented',
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            show: true,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.05),
              strokeWidth: 1,
            ),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, _) => Text(
                  val.toInt().toString(),
                  style: const TextStyle(
                      color: Color(0xFF8B949E), fontSize: 10),
                ),
                reservedSize: 28,
              ),
            ),
            bottomTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF3FB950),
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF3FB950).withValues(alpha: 0.08),
              ),
            ),
          ],
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(
              y: 30,
              color: const Color(0xFFFF3D3D).withValues(alpha: 0.4),
              strokeWidth: 1,
              dashArray: [4, 4],
              label: HorizontalLineLabel(
                show: true,
                labelResolver: (_) => 'High Risk',
                style: const TextStyle(
                    color: Color(0xFFFF3D3D), fontSize: 9),
              ),
            ),
            HorizontalLine(
              y: 60,
              color: const Color(0xFFF0883E).withValues(alpha: 0.4),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Speed Chart ──────────────────────────────────────────────
class _SpeedChart extends StatelessWidget {
  final List<GpsPoint> trail;
  const _SpeedChart({required this.trail});

  @override
  Widget build(BuildContext context) {
    if (trail.isEmpty) return const _NoDataPlaceholder();

    final spots = trail.asMap().entries.map((e) {
      return FlSpot(
          e.key.toDouble(), (e.value.speed * 3.6)); // m/s to km/h
    }).toList();

    return _ChartCard(
      title: 'Speed Over Time',
      subtitle: 'km/h — consistent speed = stable navigation',
      child: LineChart(LineChartData(
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, _) => Text(
                '${val.toInt()}',
                style: const TextStyle(
                    color: Color(0xFF8B949E), fontSize: 10),
              ),
              reservedSize: 28,
            ),
          ),
          bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF58A6FF),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF58A6FF).withValues(alpha: 0.08),
            ),
          ),
        ],
      )),
    );
  }
}

// ─── Elevation Chart ──────────────────────────────────────────
class _ElevationChart extends StatelessWidget {
  final List<GpsPoint> trail;
  const _ElevationChart({required this.trail});

  @override
  Widget build(BuildContext context) {
    if (trail.isEmpty) return const _NoDataPlaceholder();

    final spots = trail.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.altitude);
    }).toList();

    return _ChartCard(
      title: 'Elevation Profile',
      subtitle: 'Altitude in meters over the hike',
      child: LineChart(LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, _) => Text(
                '${val.toInt()}m',
                style: const TextStyle(
                    color: Color(0xFF8B949E), fontSize: 10),
              ),
              reservedSize: 36,
            ),
          ),
          bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFFF0883E),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF0883E).withValues(alpha: 0.3),
                  const Color(0xFFF0883E).withValues(alpha: 0.01),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      )),
    );
  }
}

// ─── Risk Trend Chart ─────────────────────────────────────────
class _RiskTrendChart extends StatelessWidget {
  final List<SafetyPrediction> predictions;
  const _RiskTrendChart({required this.predictions});

  @override
  Widget build(BuildContext context) {
    if (predictions.isEmpty) return const _NoDataPlaceholder();

    final spots = predictions.asMap().entries.map((e) {
      return FlSpot(
          e.key.toDouble(), e.value.disorientationProbability * 100);
    }).toList();

    return _ChartCard(
      title: 'Disorientation Risk Trend',
      subtitle: '% probability over time. >70% = alert triggered',
      child: LineChart(LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, _) => Text(
                '${val.toInt()}%',
                style: const TextStyle(
                    color: Color(0xFF8B949E), fontSize: 10),
              ),
              reservedSize: 30,
            ),
          ),
          bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            gradient: const LinearGradient(colors: [
              Color(0xFF3FB950),
              Color(0xFFF0883E),
              Color(0xFFFF3D3D),
            ]),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
          ),
        ],
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: 70,
            color: const Color(0xFFFF3D3D).withValues(alpha: 0.5),
            strokeWidth: 1.5,
            dashArray: [4, 4],
            label: HorizontalLineLabel(
              show: true,
              labelResolver: (_) => 'Alert threshold',
              style: const TextStyle(
                  color: Color(0xFFFF3D3D), fontSize: 9),
            ),
          ),
        ]),
      )),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Color(0xFFE6EDF3),
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF8B949E), fontSize: 12)),
                  const SizedBox(height: 20),
                  SizedBox(height: 220, child: child),
                ]),
          ),
        ),
      ]),
    );
  }
}

class _NoDataPlaceholder extends StatelessWidget {
  const _NoDataPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bar_chart, color: Color(0xFF30363D), size: 56),
        SizedBox(height: 12),
        Text('No data yet',
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 14)),
        Text('Start a hike to collect analytics',
            style: TextStyle(color: Color(0xFF30363D), fontSize: 12)),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.analytics_outlined,
            color: Color(0xFF30363D), size: 64),
        const SizedBox(height: 16),
        const Text('No active session',
            style: TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 16,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        const Text('Start a hike from the Dashboard',
            style: TextStyle(color: Color(0xFF30363D), fontSize: 13)),
        const SizedBox(height: 24),
        TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: Color(0xFF3FB950)),
            label: const Text('Refresh',
                style: TextStyle(color: Color(0xFF3FB950)))),
      ]),
    );
  }
}
