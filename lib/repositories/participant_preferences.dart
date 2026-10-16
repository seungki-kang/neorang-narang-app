part of '../main.dart';

class ParticipantPreferences {
  const ParticipantPreferences({this.myName = '', this.recentPartners = const []});
  final String myName;
  final List<String> recentPartners;
}

class ParticipantPreferencesRepository {
  static const storageKey = 'neorang_narang_participants_v1';

  Future<ParticipantPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return const ParticipantPreferences();
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final partners = (data['recentPartners'] as List<dynamic>).cast<String>();
      return ParticipantPreferences(
        myName: data['myName'] as String,
        recentPartners: List.unmodifiable(partners),
      );
    } catch (_) {
      throw const StorageReadException();
    }
  }

  Future<void> _write(ParticipantPreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(storageKey, jsonEncode({
      'myName': value.myName,
      'recentPartners': value.recentPartners,
    }));
    if (!saved) throw StateError('participant_write_failed');
  }

  Future<ParticipantPreferences> remember(String myName, String? partner) async {
    final old = await load();
    final name = myName.trim();
    if (name.isEmpty) throw ArgumentError('participant_name_required');
    final selected = partner?.trim() ?? '';
    final recent = selected.isEmpty
        ? old.recentPartners
        : [selected, ...old.recentPartners.where((p) => p != selected)].take(5).toList();
    final value = ParticipantPreferences(myName: name, recentPartners: recent);
    await _write(value);
    return value;
  }

  Future<ParticipantPreferences> removePartner(String partner) async {
    final old = await load();
    final value = ParticipantPreferences(
      myName: old.myName,
      recentPartners: old.recentPartners.where((p) => p != partner).toList(),
    );
    await _write(value);
    return value;
  }
}
