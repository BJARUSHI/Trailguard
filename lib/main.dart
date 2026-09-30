import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/services/alert_service.dart';
import 'core/services/offline_tile_provider.dart';
import 'core/services/stillness_detection_service.dart';
import 'core/services/hiking_session_service.dart';
import 'core/models/gps_point.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/sessions/sessions_screen.dart';
import 'features/map/map_screen.dart';
import 'features/emergency/emergency_screen.dart';
import 'features/emergency/stillness_check_dialog.dart';
import 'features/emergency/disorientation_check_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await AlertService.instance.initialize();
  await DynamicOfflineTileProvider.initPath();
  await StillnessDetectionService.instance.initialize();
  runApp(const TrailGuardApp());
}

class TrailGuardApp extends StatefulWidget {
  const TrailGuardApp({super.key});

  @override
  State<TrailGuardApp> createState() => _TrailGuardAppState();
}

class _TrailGuardAppState extends State<TrailGuardApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<GpsPoint>? _stillnessSub;
  StreamSubscription<dynamic>? _predSub;
  bool _disorientationDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _stillnessSub = StillnessDetectionService.instance.triggerStream.listen(_onStillnessTriggered);
    _predSub = HikingSessionService.instance.predictionStream.listen(_onPrediction);
  }

  void _onPrediction(dynamic pred) {
    if (pred.riskLevel.toString().contains('disoriented') && !_disorientationDialogShowing) {
      _disorientationDialogShowing = true;
      final navState = _navigatorKey.currentState;
      if (navState != null) {
        navState.push(
          PageRouteBuilder(
            opaque: true,
            fullscreenDialog: true,
            pageBuilder: (_, __, ___) => const DisorientationCheckDialog(),
          ),
        ).then((_) {
          // Dialog closed
        });
      }
    } else if (!pred.riskLevel.toString().contains('disoriented')) {
      _disorientationDialogShowing = false;
    }
  }

  void _onStillnessTriggered(GpsPoint point) {
    final navState = _navigatorKey.currentState;
    if (navState == null) return;
    navState.push(
      PageRouteBuilder(
        opaque: true,
        fullscreenDialog: true,
        pageBuilder: (_, __, ___) => StillnessCheckDialog(triggerPoint: point),
      ),
    );
  }

  @override
  void dispose() {
    _stillnessSub?.cancel();
    _predSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'TrailGuard',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const MainNavigationScreen(),
    );
  }

  ThemeData _buildTheme() {
    const bg = Color(0xFF0D1117);
    const surface = Color(0xFF161B22);
    const card = Color(0xFF1C2128);
    const accent = Color(0xFF3FB950);
    const caution = Color(0xFFF0883E);
    const danger = Color(0xFFFF3D3D);
    const textPrimary = Color(0xFFE6EDF3);
    const textSecondary = Color(0xFF8B949E);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: caution,
        error: danger,
        surface: surface,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: textPrimary,
      ),
      cardTheme: const CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: textPrimary, fontSize: 32, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 14),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 13),
        labelSmall: TextStyle(color: textSecondary, fontSize: 11, letterSpacing: 0.8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final _screens = const [
    DashboardScreen(),
    MapScreen(),
    SessionsScreen(),
    EmergencyScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          selectedIndex: _currentIndex,
          indicatorColor: const Color(0xFF3FB950).withValues(alpha: 0.15),
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: Color(0xFF3FB950)),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map, color: Color(0xFF3FB950)),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history, color: Color(0xFF3FB950)),
              label: 'Sessions',
            ),
            NavigationDestination(
              icon: Icon(Icons.emergency_outlined),
              selectedIcon: Icon(Icons.emergency, color: Color(0xFFFF3D3D)),
              label: 'SOS',
            ),
          ],
        ),
      ),
    );
  }
}
