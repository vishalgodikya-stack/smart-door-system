// person_model.dart

class PersonModel {
  final int id;
  final String name;
  final String? photoUrl;
  final String? addedByName;
  final DateTime addedAt;

  PersonModel({
    required this.id,
    required this.name,
    this.photoUrl,
    this.addedByName,
    required this.addedAt,
  });

  static DateTime _parseUtcToLocal(String raw) {
    final normalized = (raw.endsWith('Z') || raw.contains('+')) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toLocal();
  }

  factory PersonModel.fromJson(Map<String, dynamic> json) => PersonModel(
        id: json['id'],
        name: json['name'],
        photoUrl: json['photo_url'],
        addedByName: json['added_by_name'],
        addedAt: _parseUtcToLocal(json['added_at']),
      );
}
