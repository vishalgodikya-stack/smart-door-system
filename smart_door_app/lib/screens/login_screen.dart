// login_screen.dart — Premium dark login screen
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  late AnimationController _ctrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _usernameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authProvider.notifier).login(
      _usernameCtrl.text.trim(),
      _passCtrl.text,
    );
    if (ok && mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 60),

                    // Logo
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryGlow,
                          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)],
                        ),
                        child: const Icon(Icons.shield_rounded, size: 44, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Center(
                      child: Text('Welcome Back',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text('Sign in to your SmartDoor account',
                          style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    ),
                    const SizedBox(height: 48),

                    // Error message
                    if (state.error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.dangerGlow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(state.error!, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Username field
                    const Text('Username', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _usernameCtrl,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'e.g. harish or vishal',
                        prefixIcon: Icon(Icons.person_outline, color: AppColors.textMuted, size: 20),
                      ),
                      validator: (v) => v!.isEmpty ? 'Username required' : null,
                    ),
                    const SizedBox(height: 20),

                    // Password field
                    const Text('Password', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: AppColors.textMuted, size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => v!.isEmpty ? 'Password required' : null,
                      onFieldSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 36),

                    // Login button
                    ElevatedButton(
                      onPressed: state.isLoading ? null : _login,
                      child: state.isLoading
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppColors.background)))
                          : const Text('Sign In'),
                    ),
                    const SizedBox(height: 24),

                    // Info for team members
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGlow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.shield_outlined, color: AppColors.primary, size: 16),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Need an account? Contact an Admin to have your account created.',
                            style: TextStyle(color: AppColors.primary, fontSize: 12),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
