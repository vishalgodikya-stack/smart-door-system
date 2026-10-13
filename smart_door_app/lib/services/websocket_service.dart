// websocket_service.dart — WebSocket connection to backend for real-time events
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

typedef WsEventCallback = void Function(String event, Map<String, dynamic> data);

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  bool _intentionalClose = false;

  final List<WsEventCallback> _listeners = [];

  void addListener(WsEventCallback cb) => _listeners.add(cb);
  void removeListener(WsEventCallback cb) => _listeners.remove(cb);

  Future<void> connect() async {
    _intentionalClose = false;
    try {
      final token = await AuthService().getToken();
      final uri = Uri.parse('${ApiConfig.wsEndpoint}?token=$token');
      _channel = WebSocketChannel.connect(uri);

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: () { if (!_intentionalClose) _scheduleReconnect(); },
      );

      _startHeartbeat();
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = json['event'] as String;
      final data = json['data'] as Map<String, dynamic>;
      for (final cb in _listeners) {
        cb(event, data);
      }
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      try { _channel?.sink.add(jsonEncode({'ping': true})); } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 5), connect);
  }

  void disconnect() {
    _intentionalClose = true;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
  }
}
