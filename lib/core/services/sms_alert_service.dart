import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  Map<String, String> toJson() => {'name': name, 'phone': phone};

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(name: json['name'] as String, phone: json['phone'] as String);
}

class SmsAlertService {
  SmsAlertService._();
  static final SmsAlertService instance = SmsAlertService._();

  static const _channel = MethodChannel('com.trailguard.trailguard/sms');
  static const _prefsKey = 'emergency_contacts';

  Future<List<EmergencyContact>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await prefs.setString(_prefsKey, raw);
  }

  Future<void> addContact(String name, String phone) async {
    final contacts = await getContacts();
    contacts.add(EmergencyContact(name: name, phone: phone));
    await _saveContacts(contacts);
  }

  Future<void> removeContact(int index) async {
    final contacts = await getContacts();
    if (index < 0 || index >= contacts.length) return;
    contacts.removeAt(index);
    await _saveContacts(contacts);
  }

  Future<bool> requestPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  String buildEmergencyMessage({
    required double? latitude,
    required double? longitude,
  }) {
    final lat = latitude?.toStringAsFixed(6) ?? 'Unknown';
    final lon = longitude?.toStringAsFixed(6) ?? 'Unknown';
    final mapsLink = (latitude != null && longitude != null)
        ? 'https://maps.google.com/?q=$lat,$lon'
        : 'Location unavailable';

    return 'EMERGENCY!\n'
        'I may be disoriented while hiking.\n'
        'My last known location:\n'
        'Latitude: $lat\n'
        'Longitude: $lon\n'
        'Google Maps: $mapsLink\n'
        'Please contact me immediately.';
  }

  Future<Map<String, bool>> sendEmergencyAlert({
    required double? latitude,
    required double? longitude,
  }) async {
    final granted = await requestPermission();
    if (!granted) {
      throw Exception('SMS permission was denied. Enable it in phone Settings > Apps > TrailGuard > Permissions.');
    }

    final contacts = await getContacts();
    if (contacts.isEmpty) {
      throw Exception('No emergency contacts saved yet. Add one first.');
    }

    final message = buildEmergencyMessage(latitude: latitude, longitude: longitude);
    final results = <String, bool>{};

    for (final contact in contacts) {
      try {
        final ok = await _channel.invokeMethod<bool>('sendSms', {
          'phone': contact.phone,
          'message': message,
        });
        results[contact.phone] = ok ?? false;
      } on PlatformException {
        results[contact.phone] = false;
      }
    }

    return results;
  }
}
