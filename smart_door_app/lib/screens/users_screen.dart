// users_screen.dart — Manage team members and create invite links (Admin only)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/role_badge.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  List<UserModel> _users = [];
  bool _loading = true;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _users = await _api.getUsers(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createInvite() async {
    String selectedRole = 'member';
    final emailCtrl = TextEditingController();

    final result = await showModalBottomSheet<Map<String, String>?>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Create Invite Link', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            // Role picker
            const Text('Role', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: ['member', 'viewer', 'admin'].map((role) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setModal(() => selectedRole = role),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selectedRole == role ? AppColors.primary : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selectedRole == role ? AppColors.primary : AppColors.cardBorder),
                    ),
                    child: Text(role[0].toUpperCase() + role.substring(1), textAlign: TextAlign.center,
                        style: TextStyle(color: selectedRole == role ? AppColors.background : AppColors.textSecondary,
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ),
            )).toList()),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {'role': selectedRole, 'email': emailCtrl.text}),
              child: const Text('Generate Invite Link'),
            ),
          ]),
        ),
      ),
    );

    if (result != null) {
      try {
        final invite = await _api.createInvite(result['role']!, email: result['email']?.isEmpty == true ? null : result['email']);
        if (mounted) {
          _showInviteDialog(invite['invite_url'] ?? '', invite['role'] ?? '');
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
      }
    }
  }

  void _showInviteDialog(String url, String role) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('$role Invite Link', style: const TextStyle(color: AppColors.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Share this link with your team member. It expires in 7 days.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
            child: Text(url, style: const TextStyle(color: AppColors.primary, fontSize: 12), textAlign: TextAlign.center),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ Link copied to clipboard'), backgroundColor: AppColors.success));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authProvider).user?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manage Users'),
        leading: const BackButton(),
        actions: [
          IconButton(icon: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary), onPressed: _createInvite),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.primary)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final user = _users[i];
                final isSelf = user.id == currentUserId;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isSelf ? AppColors.primary.withOpacity(0.4) : AppColors.cardBorder),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primaryGlow,
                      radius: 20,
                      child: Text(user.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(user.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                          if (isSelf) ...[const SizedBox(width: 6), const Text('(You)', style: TextStyle(color: AppColors.primary, fontSize: 12))],
                        ]),
                        const SizedBox(height: 2),
                        Text(user.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 4),
                        RoleBadge(role: user.role),
                      ]),
                    ),
                    if (!isSelf) PopupMenuButton<String>(
                      color: AppColors.card,
                      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'admin', child: Text('Make Admin', style: TextStyle(color: AppColors.textPrimary))),
                        const PopupMenuItem(value: 'member', child: Text('Make Member', style: TextStyle(color: AppColors.textPrimary))),
                        const PopupMenuItem(value: 'viewer', child: Text('Make Viewer', style: TextStyle(color: AppColors.textPrimary))),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 'delete', child: Text('Remove User', style: TextStyle(color: AppColors.danger))),
                      ],
                      onSelected: (action) async {
                        if (action == 'delete') {
                          await _api.deleteUser(user.id);
                        } else {
                          await _api.updateUserRole(user.id, action);
                        }
                        _load();
                      },
                    ),
                  ]),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createInvite,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.link_rounded),
        label: const Text('Invite'),
      ),
    );
  }
}
