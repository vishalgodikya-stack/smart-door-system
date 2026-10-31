// providers/alert_provider.dart — Alert list state
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alert_model.dart';
import '../services/api_service.dart';

class AlertState {
  final List<AlertModel> alerts;
  final bool isLoading;
  final String? error;
  const AlertState({this.alerts = const [], this.isLoading = false, this.error});

  List<AlertModel> get pending => alerts.where((a) => a.isPending).toList();
  int get pendingCount => pending.length;
}

class AlertNotifier extends Notifier<AlertState> {
  @override
  AlertState build() => const AlertState();

  Future<void> fetchAlerts() async {
    state = AlertState(alerts: state.alerts, isLoading: true);
    try {
      final list = await ApiService().getAlerts();
      state = AlertState(alerts: list);
    } catch (e) {
      state = AlertState(error: e.toString());
    }
  }

  void addFromWs(Map<String, dynamic> data, {bool isAdmin = false}) {
    final newAlert = AlertModel(
      id: data['id'],
      imageUrl: data['image_url'] ?? '',
      status: 'pending',
      alertType: data['alert_type'] ?? 'doorbell',
      createdAt: DateTime.now(),
    );
    state = AlertState(alerts: [newAlert, ...state.alerts]);
  }

  void updateAlertStatus(int id, String status) {
    final updated = state.alerts.map((a) => a.id == id
        ? AlertModel(
            id: a.id,
            imageUrl: a.imageUrl,
            status: status,
            alertType: a.alertType,
            decidedByName: a.decidedByName,
            decisionAt: DateTime.now(),
            createdAt: a.createdAt,
          )
        : a).toList();
    state = AlertState(alerts: updated);
  }

  Future<void> approve(int id) async {
    await ApiService().approveAlert(id);
    updateAlertStatus(id, 'approved');
  }

  Future<void> reject(int id) async {
    await ApiService().rejectAlert(id);
    updateAlertStatus(id, 'rejected');
  }

  Future<void> clearAllAlerts() async {
    state = AlertState(alerts: state.alerts, isLoading: true);
    try {
      await ApiService().clearAllAlerts();
      state = const AlertState(alerts: [], isLoading: false);
    } catch (_) {
      state = AlertState(alerts: state.alerts, isLoading: false);
    }
  }
}

final alertProvider = NotifierProvider<AlertNotifier, AlertState>(AlertNotifier.new);
