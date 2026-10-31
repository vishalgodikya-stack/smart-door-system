// Models for data classes
// alert_model.dart

class AlertModel {
  final int id;
  final String imageUrl;
  final String status; // pending / approved / rejected
  final String alertType; // doorbell / intruder / access_request
  final String? decidedByName;
  final DateTime? decisionAt;
  final DateTime createdAt;

  AlertModel({
    required this.id,
    required this.imageUrl,
    required this.status,
    this.alertType = 'doorbell',
    this.decidedByName,
    this.decisionAt,
    required this.createdAt,
  });

  static DateTime _parseUtcToLocal(String raw) {
    final normalized = (raw.endsWith('Z') || raw.contains('+')) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toLocal();
  }

  factory AlertModel.fromJson(Map<String, dynamic> json) => AlertModel(
        id: json['id'],
        imageUrl: json['image_url'],
        status: json['status'],
        alertType: json['alert_type'] ?? 'doorbell',
        decidedByName: json['decided_by_name'],
        decisionAt: json['decision_at'] != null ? _parseUtcToLocal(json['decision_at']) : null,
        createdAt: _parseUtcToLocal(json['created_at']),
      );

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  bool get isDoorbell => alertType == 'doorbell';
  bool get isIntruder => alertType == 'intruder';
  bool get isAccessRequest => alertType == 'access_request';
}
