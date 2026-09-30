import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

class PeerPosition {
  final String deviceId;
  final String deviceName;
  final LatLng position;
  final DateTime lastSeen;

  PeerPosition({
    required this.deviceId,
    required this.deviceName,
    required this.position,
    required this.lastSeen,
  });
}

/// Module N: Offline Peer-to-Peer Position Sharing Service via Local UDP Broadcast
class PeerPositionService {
  static final PeerPositionService instance = PeerPositionService._();
  PeerPositionService._();

  static const int udpPort = 8888;
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;

  final String _myDeviceId = const Uuid().v4().substring(0, 8);
  String _myDeviceName = 'Hiker ${_randomHikerTag()}';

  final Map<String, PeerPosition> _peers = {};
  final StreamController<Map<String, PeerPosition>> _peerController =
      StreamController<Map<String, PeerPosition>>.broadcast();

  Stream<Map<String, PeerPosition>> get activePeersStream =>
      _peerController.stream;
  Map<String, PeerPosition> get activePeers => Map.unmodifiable(_peers);

  static String _randomHikerTag() {
    final rand = (100 + (DateTime.now().millisecondsSinceEpoch % 900));
    return '#$rand';
  }

  Future<void> startBroadcasting({
    required LatLng Function() getCurrentLocation,
    String? customName,
  }) async {
    if (customName != null && customName.trim().isNotEmpty) {
      _myDeviceName = customName;
    }

    await stopBroadcasting();

    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      _socket?.broadcastEnabled = true;

      _socket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            _handleIncomingPacket(datagram.data);
          }
        }
      });

      _broadcastTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        final pos = getCurrentLocation();
        _sendBroadcast(pos);
      });
    } catch (_) {
      // Local socket fallback gracefully if socket cannot bind
    }
  }

  void _sendBroadcast(LatLng pos) {
    if (_socket == null) return;
    final payload = jsonEncode({
      'deviceId': _myDeviceId,
      'deviceName': _myDeviceName,
      'lat': pos.latitude,
      'lon': pos.longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final data = utf8.encode(payload);
    try {
      _socket?.send(data, InternetAddress('255.255.255.255'), udpPort);
    } catch (_) {}
  }

  void _handleIncomingPacket(List<int> data) {
    try {
      final str = utf8.decode(data);
      final json = jsonDecode(str) as Map<String, dynamic>;
      final deviceId = json['deviceId'] as String?;
      if (deviceId == null || deviceId == _myDeviceId) return;

      final name = json['deviceName'] as String? ?? 'Peer Hiker';
      final lat = (json['lat'] as num).toDouble();
      final lon = (json['lon'] as num).toDouble();
      final ts = json['timestamp'] as int;

      _peers[deviceId] = PeerPosition(
        deviceId: deviceId,
        deviceName: name,
        position: LatLng(lat, lon),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(ts),
      );

      // Clean up peers not seen in 30s
      final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
      _peers.removeWhere((id, p) => p.lastSeen.isBefore(cutoff));

      _peerController.add(_peers);
    } catch (_) {}
  }

  Future<void> stopBroadcasting() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _socket?.close();
    _socket = null;
  }
}
