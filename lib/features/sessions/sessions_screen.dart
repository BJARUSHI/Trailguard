import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/hiking_session.dart';
import '../../core/services/hiking_session_service.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final _sessionService = HikingSessionService.instance;
  List<HikingSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    final sessions = await _sessionService.getAllSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hike History'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSessions),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? _EmptyHistory()
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _SessionCard(session: _sessions[i]),
                  ),
                ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final HikingSession session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy · HH:mm');
    final dur = session.duration;
    final durStr = dur.inHours > 0
        ? '${dur.inHours}h ${dur.inMinutes.remainder(60)}m'
        : '${dur.inMinutes}m';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(session.name,
                  style: const TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            if (session.isActive)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF3FB950).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF3FB950).withValues(alpha: 0.5)),
                ),
                child: const Text('ACTIVE',
                    style: TextStyle(
                        color: Color(0xFF3FB950),
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            if (session.emergencyTriggered)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.emergency,
                    color: Color(0xFFFF3D3D), size: 18),
              ),
          ]),
          const SizedBox(height: 8),
          Text(fmt.format(session.startTime),
              style: const TextStyle(
                  color: Color(0xFF8B949E), fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            _StatChip(
              icon: Icons.timer_outlined,
              label: durStr,
            ),
            const SizedBox(width: 8),
            _StatChip(
              icon: Icons.route,
              label:
                  '${(session.totalDistance / 1000).toStringAsFixed(2)} km',
            ),
            if (session.hasDestination) ...[
              const SizedBox(width: 8),
              const _StatChip(
                icon: Icons.flag,
                label: 'Dest set',
                color: Color(0xFF3FB950),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _StatChip(
      {required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF8B949E);
    return Row(children: [
      Icon(icon, size: 13, color: c),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(color: c, fontSize: 12)),
    ]);
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.hiking, color: Color(0xFF30363D), size: 64),
        SizedBox(height: 16),
        Text('No hikes yet',
            style: TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 16,
                fontWeight: FontWeight.w500)),
        SizedBox(height: 8),
        Text('Your completed hikes will appear here',
            style: TextStyle(color: Color(0xFF30363D), fontSize: 13)),
      ]),
    );
  }
}
