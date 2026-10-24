import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import 'api_service.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Initialize Local Notifications (for foreground & custom popups)
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && int.tryParse(payload) != null) {
          navigateToAlert(int.parse(payload));
        }
      },
    );

    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    // Register high-importance notification channel with Android OS
    const channel = AndroidNotificationChannel(
      'security_alerts',
      'Security Alerts',
      description: 'Doorbell and intruder security alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    await androidPlugin?.createNotificationChannel(channel);

    // 2. Initialize Firebase Messaging Permissions & Foreground Display
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    await _fcm.setForegroundNotificationPresentationOptions(
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

    // 3. Cold Start from terminated state
    _fcm.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        final alertIdStr = message.data['alert_id'];
        if (alertIdStr != null && int.tryParse(alertIdStr.toString()) != null) {
          Future.delayed(const Duration(milliseconds: 700), () {
            navigateToAlert(int.parse(alertIdStr.toString()));
          });
        }
      }
    });

    // 4. Background notification tap (app resumed from background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final alertIdStr = message.data['alert_id'];
      if (alertIdStr != null && int.tryParse(alertIdStr.toString()) != null) {
        navigateToAlert(int.parse(alertIdStr.toString()));
      }
    });

    // 5. Foreground Firebase message listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title = message.notification?.title ?? '🔔 Doorbell Ring';
      final body = message.notification?.body ?? 'Someone is at the door! Tap to allow or deny.';
      final alertIdStr = message.data['alert_id'];
      final imageUrl = message.data['image_url'] ?? message.notification?.android?.imageUrl;
      final alertId = alertIdStr != null ? int.tryParse(alertIdStr.toString()) : null;

      await showAlertNotification(
        id: alertId ?? message.hashCode,
        title: title,
        body: body,
        imageUrl: imageUrl,
        payload: alertId?.toString(),
      );
    });
  }

  static Future<void> showAlertNotification({
    required int id,
    required String title,
    required String body,
    String? imageUrl,
    String? payload,
  }) async {
    ByteArrayAndroidBitmap? pictureBitmap;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          pictureBitmap = ByteArrayAndroidBitmap(resp.bodyBytes);
        }
      } catch (_) {}
    }

    final AndroidNotificationDetails androidDetails;
    if (pictureBitmap != null) {
      androidDetails = AndroidNotificationDetails(
        'security_alerts',
        'Security Alerts',
        channelDescription: 'Doorbell and intruder security alerts',
        importance: Importance.max,
        priority: Priority.high,
        styleInformation: BigPictureStyleInformation(
          pictureBitmap,
          largeIcon: pictureBitmap,
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: true,
        ),
        showWhen: true,
      );
    } else {
      androidDetails = const AndroidNotificationDetails(
        'security_alerts',
        'Security Alerts',
        channelDescription: 'Doorbell and intruder security alerts',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );
    }

    await _local.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
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
