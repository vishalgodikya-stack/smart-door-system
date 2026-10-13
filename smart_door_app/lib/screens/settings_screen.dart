// settings_screen.dart - App settings and server URL config
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../config/api_config.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings'), leading: const BackButton()),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Profile card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
              gradient: LinearGradient(
                colors: [AppColors.primaryGlow, AppColors.card],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
            ),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.2),
                radius: 28,
                child: Text(user?.name.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.name ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
                Text(user?.email ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ])),
            ]),
          ),
          const SizedBox(height: 28),

          // Server info
          const _SectionHeader('Connection'),
          _InfoTile(label: 'Server URL', value: ApiConfig.httpBase, icon: Icons.dns_rounded, color: AppColors.primary),
          _InfoTile(label: 'WebSocket', value: ApiConfig.wsEndpoint, icon: Icons.sync_rounded, color: AppColors.success),
          const SizedBox(height: 20),

          // Account info
          const _SectionHeader('Account'),
          _InfoTile(label: 'Role', value: user?.role.toUpperCase() ?? '-', icon: Icons.badge_rounded, color: AppColors.warning),
          const SizedBox(height: 20),

          // App info
          const _SectionHeader('About'),
          _InfoTile(label: 'App Version', value: '1.0.0', icon: Icons.info_outline_rounded, color: AppColors.textMuted),
          _InfoTile(label: 'Backend', value: 'FastAPI + SQLite (Self-hosted)', icon: Icons.storage_rounded, color: AppColors.textMuted),
          _InfoTile(label: 'Real-time', value: 'WebSocket', icon: Icons.bolt_rounded, color: AppColors.textMuted),
          const SizedBox(height: 30),

          // Sign out
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
            label: const Text('Sign Out', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
  );
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _InfoTile({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      const Spacer(),
      Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );
}
