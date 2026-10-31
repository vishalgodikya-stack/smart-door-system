// alert_detail_screen.dart — Full visitor photo with approve/reject actions
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/alert_model.dart';
import '../providers/alert_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class AlertDetailScreen extends ConsumerStatefulWidget {
  final int alertId;
  const AlertDetailScreen({super.key, required this.alertId});

  @override
  ConsumerState<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends ConsumerState<AlertDetailScreen> {
  bool _deciding = false;

  Future<void> _decide(bool approve) async {
    setState(() => _deciding = true);
    try {
      if (approve) {
        await ref.read(alertProvider.notifier).approve(widget.alertId);
      } else {
        await ref.read(alertProvider.notifier).reject(widget.alertId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve ? '✅ Access approved — door unlocked' : '❌ Access rejected'),
          backgroundColor: approve ? AppColors.success : AppColors.danger,
        ));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertState = ref.watch(alertProvider);
    final alert = alertState.alerts.where((a) => a.id == widget.alertId).firstOrNull;
    final canDecide = ref.watch(authProvider).user?.canControl ?? false;

    if (alert == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Alert')),
        body: const Center(child: Text('Alert not found', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_appBarTitle(alert)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Full-width visitor photo
            Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: alert.imageUrl,
                  width: double.infinity,
                  height: 320,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    height: 320,
                    color: AppColors.card,
                    child: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.primary))),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 320,
                    color: AppColors.card,
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.person_outline, size: 80, color: AppColors.textMuted),
                      SizedBox(height: 12),
                      Text('Photo unavailable', style: TextStyle(color: AppColors.textMuted)),
                    ]),
                  ),
                ),

                // Status overlay
                Positioned(top: 16, right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _statusColor(alert.status).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(alert.status.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                  ),
                ),

                // Gradient overlay at bottom
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                          colors: [AppColors.background, AppColors.background.withOpacity(0)]),
                    ),
                  ),
                ),
              ],
            ),

            // Info & actions
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timestamp
                  Row(children: [
                    const Icon(Icons.access_time_rounded, color: AppColors.textMuted, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM dd, yyyy  HH:mm:ss').format(alert.createdAt.toLocal()),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(
                    _headingTitle(alert),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Warning box for pending
                  if (alert.isPending)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _alertColor(alert).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _alertColor(alert).withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        Icon(_alertIcon(alert), color: _alertColor(alert), size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _pendingDescription(alert),
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          ),
                        ),
                      ]),
                    ),

                  if (alert.isApproved || alert.isRejected) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (alert.isApproved ? AppColors.success : AppColors.danger).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: (alert.isApproved ? AppColors.success : AppColors.danger).withOpacity(0.3)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(alert.isApproved ? '✅ Access Approved' : '❌ Access Rejected',
                            style: TextStyle(color: alert.isApproved ? AppColors.success : AppColors.danger,
                                fontWeight: FontWeight.w600, fontSize: 15)),
                        if (alert.decidedByName != null) ...[
                          const SizedBox(height: 6),
                          Text('By: ${alert.decidedByName}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ]),
                    ),
                  ],

                  // Approve / Reject buttons (pending only & canControl)
                  if (alert.isPending && canDecide) ...[
                    const SizedBox(height: 28),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _deciding ? null : () => _decide(false),
                          icon: const Icon(Icons.close_rounded, color: AppColors.danger),
                          label: const Text('REJECT', style: TextStyle(color: AppColors.danger)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger),
                            foregroundColor: AppColors.danger,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _deciding ? null : () => _decide(true),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('APPROVE'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                        ),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return AppColors.success;
      case 'rejected': return AppColors.danger;
      default: return AppColors.warning;
    }
  }

  String _appBarTitle(AlertModel a) {
    switch (a.alertType) {
      case 'intruder':
        return 'Unauthorized Person';
      case 'access_request':
        return 'Access Request';
      case 'doorbell':
      default:
        return 'Doorbell Alert';
    }
  }

  String _headingTitle(AlertModel a) {
    switch (a.alertType) {
      case 'intruder':
        return 'Unauthorized Person Detected';
      case 'access_request':
        return 'Access Request';
      case 'doorbell':
      default:
        return 'Someone at the Door';
    }
  }

  String _pendingDescription(AlertModel a) {
    switch (a.alertType) {
      case 'intruder':
        return 'An unrecognized face was detected at the door. Do you want to allow or deny entry?';
      case 'access_request':
        return 'Someone is requesting access to the front door. Do you want to allow or deny entry?';
      case 'doorbell':
      default:
        return 'Someone is at the door. Do you want to allow or deny entry?';
    }
  }

  IconData _alertIcon(AlertModel a) {
    switch (a.alertType) {
      case 'intruder':
        return Icons.warning_amber_rounded;
      case 'access_request':
        return Icons.person_pin_circle_outlined;
      case 'doorbell':
      default:
        return Icons.doorbell_rounded;
    }
  }

  Color _alertColor(AlertModel a) {
    switch (a.alertType) {
      case 'intruder':
        return const Color(0xFFFF9800);
      case 'access_request':
        return const Color(0xFF29B6F6);
      case 'doorbell':
      default:
        return AppColors.warning;
    }
  }
}
