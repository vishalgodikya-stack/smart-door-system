// history_screen.dart — Access log with filter chips
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/log_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<LogModel> _logs = [];
  bool _loading = true;
  String _filter = 'all'; // all / authorized / unauthorized

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final type = _filter == 'all' ? null : _filter;
      _logs = await ApiService().getLogs(type: type);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Access History'),
        leading: const BackButton(),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              _Chip('All', 'all', _filter, (f) { setState(() => _filter = f); _load(); }),
              const SizedBox(width: 8),
              _Chip('Authorized', 'authorized', _filter, (f) { setState(() => _filter = f); _load(); }),
              const SizedBox(width: 8),
              _Chip('Unauthorized', 'unauthorized', _filter, (f) { setState(() => _filter = f); _load(); }),
            ]),
          ),
          const SizedBox(height: 12),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.primary))))
          else if (_logs.isEmpty)
            const Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.history_rounded, size: 64, color: AppColors.textMuted),
              SizedBox(height: 16),
              Text('No logs yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            ])))
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _logs.length,
                itemBuilder: (_, i) => _LogItem(log: _logs[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;
  const _Chip(this.label, this.value, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.cardBorder),
        ),
        child: Text(label, style: TextStyle(
          color: isSelected ? AppColors.background : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          fontSize: 13,
        )),
      ),
    );
  }
}

class _LogItem extends StatelessWidget {
  final LogModel log;
  const _LogItem({required this.log});

  @override
  Widget build(BuildContext context) {
    final isAuth = log.isAuthorized;
    final color = isAuth ? AppColors.success : AppColors.danger;
    final icon = _actionIcon(log.action);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(log.personName ?? 'Unknown Person',
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 3),
            Text(_actionLabel(log.action, log.performedByName),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 10),
        Text(
          DateFormat('HH:mm\nMMM d').format(log.createdAt.toLocal()),
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          textAlign: TextAlign.right,
        ),
      ]),
    );
  }

  IconData _actionIcon(String? action) {
    switch (action) {
      case 'auto_opened': return Icons.face_rounded;
      case 'approved': return Icons.check_circle_rounded;
      case 'rejected': return Icons.cancel_rounded;
      case 'pin_used': return Icons.pin_rounded;
      case 'otp_used': return Icons.security_rounded;
      case 'remote_unlock': return Icons.lock_open_rounded;
      case 'remote_lock': return Icons.lock_rounded;
      default: return Icons.door_front_door_rounded;
    }
  }

  String _actionLabel(String? action, String? by) {
    switch (action) {
      case 'auto_opened': return 'Face recognized — auto opened';
      case 'approved': return 'Approved by ${by ?? 'owner'}';
      case 'rejected': return 'Rejected by ${by ?? 'owner'}';
      case 'pin_used': return 'PIN access';
      case 'otp_used': return 'OTP access';
      case 'remote_unlock': return 'Remotely unlocked by ${by ?? 'owner'}';
      case 'remote_lock': return 'Remotely locked by ${by ?? 'owner'}';
      default: return action ?? 'Unknown action';
    }
  }
}
