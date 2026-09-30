import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../constants/app_constants.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);
    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _createTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Sessions Table
    await db.execute('''
      CREATE TABLE ${TableNames.sessions} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        start_lat REAL,
        start_lon REAL,
        dest_lat REAL,
        dest_lon REAL,
        total_distance REAL DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        emergency_triggered INTEGER DEFAULT 0,
        notes TEXT
      )
    ''');

    // GPS Points Table
    await db.execute('''
      CREATE TABLE ${TableNames.gpsPoints} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        speed REAL,
        bearing REAL,
        accuracy REAL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES ${TableNames.sessions}(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_gps_session ON ${TableNames.gpsPoints}(session_id, timestamp)'
    );

    // Features Table
    await db.execute('''
      CREATE TABLE ${TableNames.features} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        direction_variance REAL,
        backtracking_ratio REAL,
        path_efficiency REAL,
        loop_score REAL,
        movement_entropy REAL,
        speed_stability REAL,
        stop_frequency REAL,
        elevation_change REAL,
        terrain_slope REAL,
        progress_toward_dest REAL,
        FOREIGN KEY (session_id) REFERENCES ${TableNames.sessions}(id)
      )
    ''');

    // Predictions Table
    await db.execute('''
      CREATE TABLE ${TableNames.predictions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        disorientation_probability REAL NOT NULL,
        confidence_score INTEGER NOT NULL,
        risk_level TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES ${TableNames.sessions}(id)
      )
    ''');

    // Safe Zones Table
    await db.execute('''
      CREATE TABLE ${TableNames.safeZones} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        center_lat REAL NOT NULL,
        center_lon REAL NOT NULL,
        radius_meters REAL DEFAULT 50,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES ${TableNames.sessions}(id)
      )
    ''');

    // Emergency Logs Table
    await db.execute('''
      CREATE TABLE ${TableNames.emergencyLogs} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        last_lat REAL,
        last_lon REAL,
        message TEXT,
        sent INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES ${TableNames.sessions}(id)
      )
    ''');

    // Offline Regions Table
    await db.execute('''
      CREATE TABLE ${TableNames.offlineRegions} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        min_lat REAL NOT NULL,
        max_lat REAL NOT NULL,
        min_lon REAL NOT NULL,
        max_lon REAL NOT NULL,
        min_zoom INTEGER NOT NULL,
        max_zoom INTEGER NOT NULL,
        tile_count INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // Offline Waypoints Table
    await db.execute('''
      CREATE TABLE ${TableNames.offlineWaypoints} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        notes TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  // ─── GPS Points ───────────────────────────────────────────────
  Future<int> insertGpsPoint(Map<String, dynamic> point) async {
    final db = await database;
    return db.insert(TableNames.gpsPoints, point);
  }

  Future<List<Map<String, dynamic>>> getGpsPoints(String sessionId,
      {int? limit}) async {
    final db = await database;
    return db.query(
      TableNames.gpsPoints,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getRecentGpsPoints(
      String sessionId, int count) async {
    final db = await database;
    return db.query(
      TableNames.gpsPoints,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp DESC',
      limit: count,
    );
  }

  // ─── Sessions ─────────────────────────────────────────────────
  Future<int> insertSession(Map<String, dynamic> session) async {
    final db = await database;
    return db.insert(TableNames.sessions, session);
  }

  Future<int> updateSession(Map<String, dynamic> session, String id) async {
    final db = await database;
    return db.update(TableNames.sessions, session,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getActiveSession() async {
    final db = await database;
    final results = await db.query(
      TableNames.sessions,
      where: 'is_active = 1',
      orderBy: 'start_time DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final db = await database;
    return db.query(TableNames.sessions, orderBy: 'start_time DESC');
  }

  // ─── Features ─────────────────────────────────────────────────
  Future<int> insertFeatures(Map<String, dynamic> features) async {
    final db = await database;
    return db.insert(TableNames.features, features);
  }

  Future<List<Map<String, dynamic>>> getFeatureHistory(
      String sessionId) async {
    final db = await database;
    return db.query(
      TableNames.features,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

  // ─── Predictions ──────────────────────────────────────────────
  Future<int> insertPrediction(Map<String, dynamic> prediction) async {
    final db = await database;
    return db.insert(TableNames.predictions, prediction);
  }

  Future<List<Map<String, dynamic>>> getPredictionHistory(
      String sessionId) async {
    final db = await database;
    return db.query(
      TableNames.predictions,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

  // ─── Safe Zones ───────────────────────────────────────────────
  Future<int> insertSafeZone(Map<String, dynamic> zone) async {
    final db = await database;
    return db.insert(TableNames.safeZones, zone);
  }

  Future<List<Map<String, dynamic>>> getSafeZones(String sessionId) async {
    final db = await database;
    return db.query(
      TableNames.safeZones,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  // ─── Emergency Logs ───────────────────────────────────────────
  Future<int> insertEmergencyLog(Map<String, dynamic> log) async {
    final db = await database;
    return db.insert(TableNames.emergencyLogs, log);
  }

  Future<int> markEmergencyLogSent(int id) async {
    final db = await database;
    return db.update(TableNames.emergencyLogs, {'sent': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getPendingEmergencyLogs() async {
    final db = await database;
    return db.query(
      TableNames.emergencyLogs,
      where: 'sent = 0',
    );
  }

  // ─── Offline Regions ─────────────────────────────────────────
  Future<int> insertOfflineRegion(Map<String, dynamic> region) async {
    final db = await database;
    return db.insert(TableNames.offlineRegions, region,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAllOfflineRegions() async {
    final db = await database;
    return db.query(TableNames.offlineRegions, orderBy: 'created_at DESC');
  }

  Future<int> deleteOfflineRegion(String id) async {
    final db = await database;
    return db.delete(TableNames.offlineRegions,
        where: 'id = ?', whereArgs: [id]);
  }

  // ─── Offline Waypoints ────────────────────────────────────────
  Future<int> insertWaypoint(Map<String, dynamic> wp) async {
    final db = await database;
    return db.insert(TableNames.offlineWaypoints, wp,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAllWaypoints() async {
    final db = await database;
    return db.query(TableNames.offlineWaypoints, orderBy: 'name ASC');
  }

  Future<List<Map<String, dynamic>>> searchWaypoints(String query) async {
    final db = await database;
    return db.query(
      TableNames.offlineWaypoints,
      where: 'name LIKE ? OR category LIKE ? OR notes LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'name ASC',
    );
  }

  Future<int> deleteWaypoint(String id) async {
    final db = await database;
    return db.delete(TableNames.offlineWaypoints,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }
}
