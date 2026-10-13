// providers/auth_provider.dart — Auth state with Riverpod
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

final authServiceProvider = Provider((_) => AuthService());

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? error;
  const AuthState({this.user, this.isLoading = false, this.error});
  bool get isLoggedIn => user != null;
  AuthState copyWith({UserModel? user, bool? isLoading, String? error, bool clearError = false}) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<bool> checkAuth() async {
    final svc = ref.read(authServiceProvider);
    final user = await svc.getCurrentUser();
    state = AuthState(user: user);
    return user != null;
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final svc = ref.read(authServiceProvider);
      final data = await svc.login(email, password);
      final user = UserModel.fromJson(data['user']);
      state = AuthState(user: user);
      
      // Sync FCM Token immediately after login
      NotificationService().init();
      
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  Future<void> logout() async {
    await ref.read(authServiceProvider).logout();
    state = const AuthState();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
