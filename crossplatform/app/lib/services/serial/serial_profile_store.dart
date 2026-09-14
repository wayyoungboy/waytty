import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/serial_models.dart';

class SerialProfile {
  SerialProfile({String? id, required this.name, required this.config})
    : id = id ?? const Uuid().v4();
  final String id, name;
  final SerialConfig config;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'config': config.toJson(),
  };
  factory SerialProfile.fromJson(Map<String, dynamic> json) => SerialProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    config: SerialConfig.fromJson(
      Map<String, dynamic>.from(json['config'] as Map),
    ),
  );
}

class SerialProfileStore {
  static const _key = 'waytty.serial.profiles.v1';
  static Future<void> _writes = Future.value();
  Future<List<SerialProfile>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map(
            (v) => SerialProfile.fromJson(Map<String, dynamic>.from(v as Map)),
          )
          .toList();
    } catch (_) {
      throw const FormatException('Saved serial profiles are damaged');
    }
  }

  Future<void> save(SerialProfile profile) => _update((profiles) {
    profile.config.validate();
    if (profile.name.trim().isEmpty || profile.name.length > 100) {
      throw const FormatException('Invalid serial profile name');
    }
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index < 0) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
  });
  Future<void> delete(String id) =>
      _update((profiles) => profiles.removeWhere((p) => p.id == id));
  Future<void> _update(void Function(List<SerialProfile>) change) {
    final result = _writes.then((_) async {
      final profiles = await load(); // Refuse to overwrite corrupt data.
      change(profiles);
      final ok = await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode(profiles.map((p) => p.toJson()).toList()),
      );
      if (!ok) throw const SerialException('Cannot save serial profiles');
    });
    _writes = result.catchError((Object _) {});
    return result;
  }
}
