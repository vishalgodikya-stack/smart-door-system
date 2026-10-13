// providers/door_provider.dart — Real-time door state
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/notification_service.dart';

class DoorState {
  final String status; // locked / unlocked
  final bool isLoading;
  final DateTime? lastUpdated;
  const DoorState({this.status = 'locked', this.isLoading = false, this.lastUpdated});

  bool get isLocked => status == 'locked';
  bool get isUnlocked => status == 'unlocked';
}

class DoorNotifier extends Notifier<DoorState> {
  @override
  DoorState build() => const DoorState();

  static DateTime _parseUtcToLocal(String raw) {
    final normalized = (raw.endsWith('Z') || raw.contains('+')) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toLocal();
  }

  Future<void> fetchStatus() async {
    try {
      final data = await ApiService().getDoorStatus();
      state = DoorState(
        status: data['status'],
        lastUpdated: data['last_updated'] != null ? _parseUtcToLocal(data['last_updated']) : null,
      );
    } catch (_) {}
  }

  void updateFromWs(String status) {
    state = DoorState(status: status, lastUpdated: DateTime.now());
    NotificationService.showDoorNotification(status);
  }

  Future<void> lock() async {
    state = DoorState(status: state.status, isLoading: true);
    await ApiService().lockDoor();
    state = DoorState(status: 'locked', lastUpdated: DateTime.now());
  }

  Future<void> unlock() async {
    state = DoorState(status: state.status, isLoading: true);
    await ApiService().unlockDoor();
    state = DoorState(status: 'unlocked', lastUpdated: DateTime.now());
  }
}

final doorProvider = NotifierProvider<DoorNotifier, DoorState>(DoorNotifier.new);

// WebSocket service shared instance
final wsServiceProvider = Provider((_) => WebSocketService());
