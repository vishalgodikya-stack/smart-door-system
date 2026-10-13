// main.dart — App entry point
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'providers/alert_provider.dart';
import 'providers/door_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/alert_detail_screen.dart';
import 'screens/history_screen.dart';
import 'screens/persons_screen.dart';
import 'screens/users_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/pin_otp_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize Firebase
    await Firebase.initializeApp();
    
    // Initialize Push Notifications (in background so it doesn't hang the app)
    NotificationService().init().catchError((e) => print("Notification Init Error: $e"));
  } catch (e) {
    print("Firebase/Notification Startup Error: $e");
  }
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const ProviderScope(child: SmartDoorApp()));
}

final _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
      path: '/home',
      builder: (_, __) => const DashboardScreen(),
      routes: [
        GoRoute(path: 'alert/:id', builder: (ctx, state) {
          return AlertDetailScreen(alertId: int.parse(state.pathParameters['id']!));
        }),
        GoRoute(path: 'history', builder: (_, __) => const HistoryScreen()),
        GoRoute(path: 'persons', builder: (_, __) => const PersonsScreen()),
        GoRoute(path: 'users', builder: (_, __) => const UsersScreen()),
        GoRoute(path: 'settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: 'pin-setup', builder: (_, __) => const PinOtpScreen()),
      ],
    ),
  ],
);

class SmartDoorApp extends ConsumerWidget {
  const SmartDoorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SmartDoor',
      theme: AppTheme.dark,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
