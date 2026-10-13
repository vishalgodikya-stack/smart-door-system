// pin_otp_screen.dart — PIN and TOTP setup
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class PinOtpScreen extends ConsumerStatefulWidget {
  const PinOtpScreen({super.key});

  @override
  ConsumerState<PinOtpScreen> createState() => _PinOtpScreenState();
}

class _PinOtpScreenState extends ConsumerState<PinOtpScreen> {
  final _api = ApiService();
  String _pin = '';
  bool _savingPin = false;
  bool _setupTotp = false;

  Future<void> _savePin() async {
    if (_pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN must be at least 4 digits'), backgroundColor: AppColors.danger));
      return;
    }
    setState(() => _savingPin = true);
    try {
      await _api.setupPin(_pin);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ PIN saved successfully'), backgroundColor: AppColors.success));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _savingPin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    final pinTheme = PinTheme(
      width: 56, height: 60,
      textStyle: const TextStyle(fontSize: 22, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('PIN & OTP Setup'), leading: const BackButton()),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'PIN and OTP provide fallback access when face recognition fails.',
                  style: TextStyle(color: AppColors.primary, fontSize: 13),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 32),

          // PIN section
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primaryGlow, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.pin_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Access PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const Spacer(),
            if (user?.hasPin == true)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.successGlow, borderRadius: BorderRadius.circular(10)),
                child: const Text('Set ✓', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 8),
          const Text('Enter a 6-digit PIN for door access when face recognition fails.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),

          Center(
            child: Pinput(
              length: 6,
              obscureText: true,
              defaultPinTheme: pinTheme,
              focusedPinTheme: pinTheme.copyWith(
                decoration: pinTheme.decoration!.copyWith(
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
              ),
              onChanged: (v) => setState(() => _pin = v),
              onCompleted: (v) => setState(() => _pin = v),
            ),
          ),
          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: _savingPin ? null : _savePin,
            child: _savingPin
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppColors.background)))
                : Text(user?.hasPin == true ? 'Update PIN' : 'Set PIN'),
          ),
          const SizedBox(height: 40),
          const Divider(color: AppColors.cardBorder),
          const SizedBox(height: 32),

          // TOTP section
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.successGlow, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.security_rounded, color: AppColors.success, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Authenticator OTP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const Spacer(),
            if (user?.hasTotp == true)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.successGlow, borderRadius: BorderRadius.circular(10)),
                child: const Text('Set ✓', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 8),
          const Text('Scan the QR code with Google Authenticator or any TOTP app for a rotating 6-digit code.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: _setupTotp ? null : () async {
              setState(() => _setupTotp = true);
              try {
                final bytes = await _api.setupTotp();
                if (!mounted) return;
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.card,
                    title: const Text('Scan QR Code', style: TextStyle(color: AppColors.textPrimary)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Open Google Authenticator and scan this code to add your SmartDoor account.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                          child: Image.memory(
                            Uint8List.fromList(bytes),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          // Force a refresh of the user object to show "Set ✓"
                          ref.read(authProvider.notifier).checkAuth();
                        },
                        child: const Text('Done'),
                      )
                    ],
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
                );
              } finally {
                if (mounted) setState(() => _setupTotp = false);
              }
            },
            icon: _setupTotp
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.qr_code_scanner_rounded),
            label: Text(user?.hasTotp == true ? 'Regenerate TOTP Secret' : 'Setup Authenticator OTP'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
          ),
        ]),
      ),
    );
  }
}
