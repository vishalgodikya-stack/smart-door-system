// users_screen.dart — Manage team members, reset sessions, and create users (Admin only)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    try {
      _users = await _api.getUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _adminCount => _users.where((u) => u.isAdmin).length;

  Future<void> _openAddUserModal() async {
    String selectedRole = 'member';
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;
    final currentAdminCount = _adminCount;
    final maxAdminsReached = currentAdminCount >= 2;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.primaryGlow, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text('Add New User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 20),

                // Username field
                const Text('Username', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: usernameCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'e.g. harish or john',
                    prefixIcon: Icon(Icons.person_outline, color: AppColors.textMuted, size: 20),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Username is required';
                    if (v.trim().contains(' ')) return 'Username cannot contain spaces';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password field
                const Text('Password', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: passwordCtrl,
                  obscureText: obscure,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textMuted, size: 20),
                      onPressed: () => setModal(() => obscure = !obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                ),
                const SizedBox(height: 16),

                // Role selection
                Row(
                  children: [
                    const Text('Role', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    if (maxAdminsReached)
                      const Text('Max 2 Admins reached (2/2)', style: TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Member Option
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setModal(() => selectedRole = 'member'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedRole == 'member' ? AppColors.primary : AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: selectedRole == 'member' ? AppColors.primary : AppColors.cardBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_rounded, size: 16, color: selectedRole == 'member' ? AppColors.background : AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text('Member', style: TextStyle(
                                color: selectedRole == 'member' ? AppColors.background : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Admin Option
                    Expanded(
                      child: GestureDetector(
                        onTap: maxAdminsReached
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Max 2 Admins reached. Remove an existing admin first.'), backgroundColor: AppColors.warning),
                                );
                              }
                            : () => setModal(() => selectedRole = 'admin'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: maxAdminsReached
                                ? AppColors.surface.withOpacity(0.5)
                                : (selectedRole == 'admin' ? AppColors.primary : AppColors.surface),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: maxAdminsReached
                                  ? AppColors.cardBorder.withOpacity(0.5)
                                  : (selectedRole == 'admin' ? AppColors.primary : AppColors.cardBorder),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shield_rounded,
                                size: 16,
                                color: maxAdminsReached
                                    ? AppColors.textMuted
                                    : (selectedRole == 'admin' ? AppColors.background : AppColors.textSecondary),
                              ),
                              const SizedBox(width: 6),
                              Text('Admin', style: TextStyle(
                                color: maxAdminsReached
                                    ? AppColors.textMuted
                                    : (selectedRole == 'admin' ? AppColors.background : AppColors.textSecondary),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(ctx);
                      try {
                        await _api.createUser(
                          username: usernameCtrl.text.trim(),
                          password: passwordCtrl.text,
                          role: selectedRole,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('✅ User "${usernameCtrl.text.trim()}" created successfully!'), backgroundColor: AppColors.success),
                          );
                        }
                        _load();
                      } catch (e) {
                        if (mounted) {
                          final msg = e.toString().replaceFirst('Exception: ', '');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
                          );
                        }
                      }
                    },
                    child: const Text('Create User'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _resetSession(UserModel user) async {
    try {
      await _api.resetUserSession(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Session reset for "${user.username}"'), backgroundColor: AppColors.success),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting session: $msg'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _deleteUser(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Remove ${user.username}?', style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          user.isAdmin && _adminCount <= 1
              ? 'Cannot remove the last remaining admin in the system.'
              : 'Are you sure you want to permanently remove user "${user.username}"?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          if (!(user.isAdmin && _adminCount <= 1))
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.deleteUser(user.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User "${user.username}" removed'), backgroundColor: AppColors.success),
          );
        }
        _load();
      } catch (e) {
        if (mounted) {
          final msg = e.toString().replaceFirst('Exception: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error removing user: $msg'), backgroundColor: AppColors.danger),
          );
        }
      }
    }
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
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary),
            tooltip: 'Add User',
            onPressed: _openAddUserModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.primary)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final user = _users[i];
                final isSelf = user.id == currentUserId;
                final initial = (user.username.isNotEmpty ? user.username[0] : (user.name.isNotEmpty ? user.name[0] : 'U')).toUpperCase();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isSelf ? AppColors.primary.withOpacity(0.4) : AppColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primaryGlow,
                            radius: 20,
                            child: Text(
                              initial,
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      user.name.isNotEmpty ? user.name : user.username,
                                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    if (isSelf) ...[
                                      const SizedBox(width: 6),
                                      const Text('(You)', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500)),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '@${user.username}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          RoleBadge(role: user.role),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: AppColors.cardBorder),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // Session Status Indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: user.isLoggedIn ? AppColors.successGlow : AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: user.isLoggedIn ? AppColors.success.withOpacity(0.4) : AppColors.cardBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: user.isLoggedIn ? AppColors.success : AppColors.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  user.isLoggedIn ? 'Signed In' : 'Offline',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: user.isLoggedIn ? AppColors.success : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),

                          // Reset Session Button
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.warning,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.restart_alt_rounded, size: 16),
                            label: const Text('Reset Session', style: TextStyle(fontSize: 12)),
                            onPressed: () => _resetSession(user),
                          ),

                          // Delete action (if not self)
                          if (!isSelf)
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                              tooltip: 'Remove User',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _deleteUser(user),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddUserModal,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('+ Add User', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
