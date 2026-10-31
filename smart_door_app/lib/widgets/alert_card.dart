// widgets/alert_card.dart — Compact alert card with image thumbnail
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/alert_model.dart';
import '../theme/app_theme.dart';

class AlertCard extends StatelessWidget {
  final AlertModel alert;
  final bool canDecide;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onTap;

  const AlertCard({
    super.key,
    required this.alert,
    required this.canDecide,
    required this.onApprove,
    required this.onReject,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = _alertTypeColor(alert);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: alert.isPending ? typeColor.withOpacity(0.55) : AppColors.cardBorder,
            width: alert.isPending ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          // Thumbnail
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: CachedNetworkImage(
              imageUrl: alert.imageUrl,
              width: 90, height: 90,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.surface, width: 90, height: 90,
                  child: Icon(_alertTypeIcon(alert), color: AppColors.textMuted)),
              errorWidget: (_, __, ___) => Container(color: AppColors.surface, width: 90, height: 90,
                  child: Icon(_alertTypeIcon(alert), color: AppColors.textMuted)),
            ),
          ),

          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _StatusDot(alert.status),
                  const SizedBox(width: 6),
                  Text(_statusLabel(alert.status),
                      style: TextStyle(color: _statusColor(alert.status), fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: typeColor.withOpacity(0.35), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_alertTypeIcon(alert), size: 11, color: typeColor),
                        const SizedBox(width: 3),
                        Text(
                          alert.isIntruder ? 'CAMERA' : (alert.isAccessRequest ? 'REQUEST' : 'DOORBELL'),
                          style: TextStyle(color: typeColor, fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(DateFormat('HH:mm').format(alert.createdAt.toLocal()),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
                const SizedBox(height: 5),
                Text(
                  _alertTitle(alert),
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  _alertSubtitle(alert),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // Quick approve/reject (pending only & canDecide)
                if (alert.isPending && canDecide) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onReject,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.dangerGlow,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                          ),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.close_rounded, color: AppColors.danger, size: 14),
                            SizedBox(width: 4),
                            Text('Reject', style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: onApprove,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.successGlow,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.success.withOpacity(0.3)),
                          ),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.check_rounded, color: AppColors.success, size: 14),
                            SizedBox(width: 4),
                            Text('Approve', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
          ),

          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ),
        ]),
      ),
    );
  }

  String _alertTitle(AlertModel a) {
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

  String _alertSubtitle(AlertModel a) {
    switch (a.alertType) {
      case 'intruder':
        return 'Unrecognized face detected — tap to review';
      case 'access_request':
        return 'Someone requested entry — tap to review';
      case 'doorbell':
      default:
        return 'Doorbell ring — tap to allow or deny';
    }
  }

  IconData _alertTypeIcon(AlertModel a) {
    switch (a.alertType) {
      case 'intruder':
        return Icons.warning_amber_rounded;
      case 'access_request':
        return Icons.person_pin_circle_outlined;
      case 'doorbell':
      default:
        return Icons.doorbell_outlined;
    }
  }

  Color _alertTypeColor(AlertModel a) {
    switch (a.alertType) {
      case 'intruder':
        return const Color(0xFFFF9800); // Amber warning
      case 'access_request':
        return const Color(0xFF29B6F6); // Cyan/blue
      case 'doorbell':
      default:
        return AppColors.primary;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved': return AppColors.success;
      case 'rejected': return AppColors.danger;
      default: return AppColors.warning;
    }
  }

  String _statusLabel(String s) => s.toUpperCase();
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot(this.status);

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'approved': color = AppColors.success; break;
      case 'rejected': color = AppColors.danger; break;
      default: color = AppColors.warning; break;
    }
    return Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
  }
}
