// widgets/role_badge.dart — Color-coded role badge
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RoleBadge extends StatelessWidget {
  final String role;
  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (role) {
      case 'admin':
        color = AppColors.roleAdmin;
        icon = Icons.shield_rounded;
        break;
      case 'member':
        color = AppColors.roleMember;
        icon = Icons.people_rounded;
        break;
      default:
        color = AppColors.roleViewer;
        icon = Icons.visibility_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(role.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ]),
    );
  }
}
