// widgets/door_status_card.dart — Animated door lock/unlock card
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/door_provider.dart';
import '../theme/app_theme.dart';

class DoorStatusCard extends StatefulWidget {
  final DoorState door;
  final bool canControl;
  final VoidCallback onLock;
  final VoidCallback onUnlock;
  final VoidCallback? onReqAccess;

  const DoorStatusCard({
    super.key,
    required this.door,
    required this.canControl,
    required this.onLock,
    required this.onUnlock,
    this.onReqAccess,
  });

  @override
  State<DoorStatusCard> createState() => _DoorStatusCardState();
}

class _DoorStatusCardState extends State<DoorStatusCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = widget.door.isLocked;
    final color = isLocked ? AppColors.danger : AppColors.success;
    final label = isLocked ? 'LOCKED' : 'UNLOCKED';
    final icon = isLocked ? Icons.lock_rounded : Icons.lock_open_rounded;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 20, spreadRadius: 2)],
      ),
      child: Column(children: [
        // Lock icon with pulse animation
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.08 * _pulseAnim.value),
              boxShadow: [BoxShadow(color: color.withOpacity(0.3 * _pulseAnim.value), blurRadius: 30, spreadRadius: 5)],
            ),
            child: Icon(icon, size: 48, color: color),
          ),
        ),
        const SizedBox(height: 16),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(label, key: ValueKey(label),
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color, letterSpacing: 2)),
        ),


        if (widget.door.lastUpdated != null) ...[
          const SizedBox(height: 6),
          Text(
            'Last updated: ${DateFormat('HH:mm').format(widget.door.lastUpdated!.toLocal())}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],

        if (widget.canControl) ...[
          const SizedBox(height: 20),
          widget.door.isLoading
              ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.primary))
              : Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isLocked ? null : widget.onLock,
                      icon: const Icon(Icons.lock_rounded, size: 18),
                      label: const Text('Lock'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: BorderSide(color: isLocked ? AppColors.cardBorder : AppColors.danger),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isLocked ? widget.onUnlock : null,
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: const Text('Unlock'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isLocked ? AppColors.success : AppColors.card,
                        foregroundColor: isLocked ? Colors.white : AppColors.textMuted,
                      ),
                    ),
                  ),
                ]),
        ] else ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onReqAccess,
              icon: const Icon(Icons.front_hand_rounded, size: 20),
              label: const Text('Request Access', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
