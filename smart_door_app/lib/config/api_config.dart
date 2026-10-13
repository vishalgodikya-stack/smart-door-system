/// api_config.dart — Central configuration for API URL
/// Change SERVER_URL to your Cloudflare Tunnel / Tailscale URL when deploying
library;

class ApiConfig {
  /// Production (Tailscale Funnel / HTTPS): https://your-pi-hostname.ts.net
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://your-pi-hostname.ts.net',
  );

  static String get httpBase => baseUrl;
  static String get wsBase => baseUrl.replaceFirst('https', 'wss').replaceFirst('http', 'ws');

  // Endpoints
  static String get login => '$httpBase/auth/login';
  static String get me => '$httpBase/auth/me';
  static String get setupPin => '$httpBase/auth/setup-pin';
  static String get verifyPin => '$httpBase/auth/verify-pin';
  static String get setupTotp => '$httpBase/auth/setup-totp';
  static String get verifyOtp => '$httpBase/auth/verify-otp';
  static String get createInvite => '$httpBase/users/invite';

  static String get doorStatus => '$httpBase/door/status';
  static String get doorLock => '$httpBase/door/lock';
  static String get doorUnlock => '$httpBase/door/unlock';

  static String get alerts => '$httpBase/alerts';
  static String get requestAccess => '$httpBase/alerts/request-access';
  static String alertApprove(int id) => '$httpBase/alerts/$id/approve';
  static String alertReject(int id) => '$httpBase/alerts/$id/reject';

  static String get logs => '$httpBase/logs';
  static String get persons => '$httpBase/persons';
  static String get enrollStart => '$httpBase/persons/enroll/start';
  static String get enrollStop => '$httpBase/persons/enroll/stop';
  static String get enrollFrame => '$httpBase/persons/enroll/frame';
  static String get enrollScan => '$httpBase/persons/enroll/scan';
  static String get users => '$httpBase/users';

  static String imageUrl(String filename) => '$httpBase/images/$filename';
  static String get wsEndpoint => '$wsBase/ws';
}
