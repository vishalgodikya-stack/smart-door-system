// dashboard_screen.dart — Main hub: door control, pending alerts, face enrollment, menu
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/door_provider.dart';
import '../providers/alert_provider.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/door_status_card.dart';
import '../widgets/alert_card.dart';
import '../widgets/role_badge.dart';
import 'enroll_face_tab.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _navIndex = 0;
  late WebSocketService _ws;

  @override
  void initState() {
    super.initState();
    _ws = ref.read(wsServiceProvider);
    _ws.addListener(_onWsEvent);
    _ws.connect();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(doorProvider.notifier).fetchStatus();
      ref.read(alertProvider.notifier).fetchAlerts();
    });
  }

  void _onWsEvent(String event, Map<String, dynamic> data) {
    switch (event) {
      case 'new_alert':
        final user = ref.read(authProvider).user;
        ref.read(alertProvider.notifier).addFromWs(data, isAdmin: user?.isAdmin == true);
        break;
      case 'door_status':
        ref.read(doorProvider.notifier).updateFromWs(data['status']);
        break;
      case 'alert_updated':
        ref.read(alertProvider.notifier).updateAlertStatus(data['id'], data['status']);
        break;
    }
  }

  @override
  void dispose() {
    _ws.removeListener(_onWsEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.isAdmin == true;
    final alertState = ref.watch(alertProvider);
    final pendingCount = alertState.pendingCount;

    final tabs = <Widget>[
      const _HomeTab(),
      const _AlertsTab(),
      if (isAdmin) EnrollFaceTab(isActive: _navIndex == 2),
      const _MenuTab(),
    ];

    final navItems = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
      BottomNavigationBarItem(
        icon: Badge(
          label: pendingCount > 0 ? Text('$pendingCount') : null,
          isLabelVisible: pendingCount > 0,
          child: const Icon(Icons.notifications_rounded),
        ),
        label: 'Alerts',
      ),
      if (isAdmin)
        const BottomNavigationBarItem(
          icon: Icon(Icons.face_retouching_natural_rounded),
          label: 'Enroll Face',
        ),
      const BottomNavigationBarItem(icon: Icon(Icons.menu_rounded), label: 'Menu'),
    ];

    final safeIndex = _navIndex >= tabs.length ? 0 : _navIndex;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: safeIndex,
        children: tabs,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: safeIndex,
          onTap: (i) => setState(() => _navIndex = i),
          items: navItems,
        ),
      ),
    );
  }
}

// ─── Home Tab ───────────────────────────────────────────────────────────────────
class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final door = ref.watch(doorProvider);
    final alertState = ref.watch(alertProvider);
    final pending = alertState.pending;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primaryGlow,
                    radius: 22,
                    child: Text(
                      user?.name.substring(0, 1).toUpperCase() ?? 'U',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Hello, ${user?.name.split(' ').first ?? 'User'}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      RoleBadge(role: user?.role ?? 'member'),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                    onPressed: () {
                      ref.read(doorProvider.notifier).fetchStatus();
                      ref.read(alertProvider.notifier).fetchAlerts();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // Door Status Card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: DoorStatusCard(
                door: door,
                canControl: user?.canControl ?? false,
                onLock: () => ref.read(doorProvider.notifier).lock(),
                onUnlock: () => ref.read(doorProvider.notifier).unlock(),
                onReqAccess: () async {
                  try {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Requesting access...')),
                    );
                    await ApiService().requestAccess();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Access requested successfully!')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // Stats row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                _StatCard(label: 'Pending', value: '${alertState.pendingCount}', color: AppColors.warning, icon: Icons.pending_actions_rounded),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Today\'s Alerts',
                  value: '${alertState.alerts.where((a) => a.createdAt.day == DateTime.now().day).length}',
                  color: AppColors.primary,
                  icon: Icons.notifications_active_rounded,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Total Logs',
                  value: '${alertState.alerts.length}',
                  color: AppColors.success,
                  icon: Icons.history_rounded,
                ),
              ]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // Pending alerts section
          if (pending.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Container(width: 4, height: 18, decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  const Text('Pending Approvals', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const Spacer(),
                  Text('${pending.length}', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: AlertCard(
                    alert: pending[i],
                    canDecide: ref.read(authProvider).user?.canControl ?? false,
                    onApprove: () => ref.read(alertProvider.notifier).approve(pending[i].id),
                    onReject: () => ref.read(alertProvider.notifier).reject(pending[i].id),
                    onTap: () => context.go('/home/alert/${pending[i].id}'),
                  ),
                ),
                childCount: pending.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _StatCard({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

// ─── Alerts Tab ─────────────────────────────────────────────────────────────────
class _AlertsTab extends ConsumerWidget {
  const _AlertsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertState = ref.watch(alertProvider);
    final user = ref.watch(authProvider).user;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(children: [
              const Text('Alerts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                onPressed: () => ref.read(alertProvider.notifier).fetchAlerts(),
              ),
              if (alertState.alerts.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => ref.read(alertProvider.notifier).clearAllAlerts(),
                ),
            ]),
          ),
          if (alertState.isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.primary))))
          else if (alertState.alerts.isEmpty)
            const Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_outline, color: AppColors.success, size: 64),
              SizedBox(height: 16),
              Text('All clear!', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('No alerts detected', style: TextStyle(color: AppColors.textSecondary)),
            ])))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: alertState.alerts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final alert = alertState.alerts[i];
                  return AlertCard(
                    alert: alert,
                    canDecide: user?.canControl ?? false,
                    onApprove: () => ref.read(alertProvider.notifier).approve(alert.id),
                    onReject: () => ref.read(alertProvider.notifier).reject(alert.id),
                    onTap: () => context.go('/home/alert/${alert.id}'),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Menu Tab ────────────────────────────────────────────────────────────────────
class _MenuTab extends ConsumerWidget {
  const _MenuTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),
          const Text('Menu', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 24),
          _MenuTile(icon: Icons.history_rounded, label: 'Access History', color: AppColors.primary, onTap: () => context.go('/home/history')),
          _MenuTile(icon: Icons.people_rounded, label: 'Authorized Persons', color: AppColors.success, onTap: () => context.go('/home/persons')),
          if (user?.isAdmin == true) ...[
            _MenuTile(icon: Icons.manage_accounts_rounded, label: 'Manage Users', color: AppColors.warning, onTap: () => context.go('/home/users')),
          ],
          _MenuTile(icon: Icons.settings_rounded, label: 'Settings', color: AppColors.textSecondary, onTap: () => context.go('/home/settings')),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.logout_rounded,
            label: 'Sign Out',
            color: AppColors.danger,
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
