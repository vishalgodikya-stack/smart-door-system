// user_model.dart

class UserModel {
  final int id;
  final String name;
  final String username;
  final String role; // admin / member
  final bool isActive;
  final bool isLoggedIn;
  final DateTime createdAt;
  final bool hasPin;
  final bool hasTotp;

  UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    required this.isActive,
    this.isLoggedIn = false,
    required this.createdAt,
    required this.hasPin,
    required this.hasTotp,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        name: json['name'] ?? '',
        username: json['username'] ?? json['email'] ?? '',
        role: json['role'] ?? 'member',
        isActive: json['is_active'] ?? true,
        isLoggedIn: json['is_logged_in'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
        hasPin: json['has_pin'] ?? false,
        hasTotp: json['has_totp'] ?? false,
      );

  // Backward-compatible alias
  String get email => username;

  bool get isAdmin => role == 'admin';
  bool get isMember => role == 'member';
  bool get canControl => role == 'admin' || role == 'member';
}
