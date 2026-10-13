import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Initialize Local Notifications (for foreground popups)
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(const InitializationSettings(android: android, iOS: ios));
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // 2. Initialize Firebase Messaging
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      try {
        String? token = await _fcm.getToken();
        if (token != null) await _updateTokenOnServer(token);
      } catch (e) {
        if (kDebugMode) print('Could not get FCM token: $e');
      }
    }

    _fcm.onTokenRefresh.listen((newToken) => _updateTokenOnServer(newToken));

    // Foreground Firebase listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        showAlertNotification(
          id: message.hashCode,
          title: message.notification!.title ?? 'Alert',
          body: message.notification!.body ?? '',
        );
      }
    });
  }

  static Future<void> showAlertNotification({required int id, required String title, required String body}) async {
    const details = AndroidNotificationDetails(
      'security_alerts', 'Security Alerts',
      importance: Importance.max, priority: Priority.high,
      showWhen: true,
    );
    await _local.show(id, title, body, const NotificationDetails(android: details));
  }

  static void showDoorNotification(String status) {
    showAlertNotification(
      id: 999,
      title: status == 'unlocked' ? '🔓 Door Unlocked' : '🔒 Door Locked',
      body: status == 'unlocked' ? 'The door is now open.' : 'The door has been secured.',
    );
  }

  Future<void> _updateTokenOnServer(String token) async {
    try {
      await ApiService().updateFcmToken(token);
    } catch (e) {
      if (kDebugMode) print('FCM Error: $e');
    }
  }
}
