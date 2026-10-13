// user_model.dart

class UserModel {
  final int id;
  final String name;
  final String email;
  final String role; // admin / member / viewer
  final bool isActive;
  final DateTime createdAt;
  final bool hasPin;
  final bool hasTotp;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.hasPin,
    required this.hasTotp,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        name: json['name'],
        email: json['email'],
        role: json['role'],
        isActive: json['is_active'],
        createdAt: DateTime.parse(json['created_at']),
        hasPin: json['has_pin'] ?? false,
        hasTotp: json['has_totp'] ?? false,
      );

  bool get isAdmin => role == 'admin';
  bool get isMember => role == 'member';
  bool get isViewer => role == 'viewer';
  bool get canControl => role == 'admin' || role == 'member';
}
