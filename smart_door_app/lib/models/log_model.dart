// log_model.dart

class LogModel {
  final int id;
  final String? personName;
  final String type;   // authorized / unauthorized
  final String? action; // auto_opened / approved / rejected / pin_used / otp_used / remote_unlock / remote_lock
  final String? imageUrl;
  final String? performedByName;
  final DateTime createdAt;

  LogModel({
    required this.id,
    this.personName,
    required this.type,
    this.action,
    this.imageUrl,
    this.performedByName,
    required this.createdAt,
  });

  static DateTime _parseUtcToLocal(String raw) {
    final normalized = (raw.endsWith('Z') || raw.contains('+')) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toLocal();
  }

  factory LogModel.fromJson(Map<String, dynamic> json) => LogModel(
        id: json['id'],
        personName: json['person_name'],
        type: json['type'],
        action: json['action'],
        imageUrl: json['image_url'],
        performedByName: json['performed_by_name'],
        createdAt: _parseUtcToLocal(json['created_at']),
      );

  bool get isAuthorized => type == 'authorized';
}
