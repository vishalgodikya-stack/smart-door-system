// enroll_face_tab.dart — Live Raspberry Pi camera face enrollment tab (Admin only)
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

enum _EnrollStatus {
  idle,
  positioning,
  scanning,
  success,
  failed,
}

class EnrollFaceTab extends StatefulWidget {
  final bool isActive;

  const EnrollFaceTab({
    super.key,
    required this.isActive,
  });

  @override
  State<EnrollFaceTab> createState() => _EnrollFaceTabState();
}

class _EnrollFaceTabState extends State<EnrollFaceTab> with WidgetsBindingObserver {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();

  _EnrollStatus _status = _EnrollStatus.idle;
  String _statusMessage = 'Enter the person\'s name and press Start Face Registration.';
  bool _isStreaming = false;
  Uint8List? _currentFrame;

  Timer? _frameTimer;
  Timer? _scanTimer;
  Timer? _timeoutTimer;

  bool _fetchingFrame = false;
  bool _scanningFace = false;
  int _sessionToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant EnrollFaceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stop camera stream immediately if user switches to another bottom navigation tab
    if (oldWidget.isActive && !widget.isActive && _isStreaming) {
      _stopStream(
        notifyBackend: true,
        nextStatus: _EnrollStatus.idle,
        nextMessage: 'Camera stream stopped because you left the Enroll Face tab.',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop camera stream if the app is backgrounded or closed
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _isStreaming) {
      _stopStream(
        notifyBackend: true,
        nextStatus: _EnrollStatus.idle,
        nextMessage: 'Camera stream stopped.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimers();
    if (_isStreaming) {
      _api.stopFaceEnrollment();
    }
    _nameCtrl.dispose();
    super.dispose();
  }

  void _cancelTimers() {
    _frameTimer?.cancel();
    _frameTimer = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  Future<void> _stopStream({
    required bool notifyBackend,
    _EnrollStatus? nextStatus,
    String? nextMessage,
    bool keepLastFrame = false,
  }) async {
    _sessionToken++;
    _cancelTimers();
    _fetchingFrame = false;
    _scanningFace = false;

    if (mounted) {
      setState(() {
        _isStreaming = false;
        if (!keepLastFrame) {
          _currentFrame = null;
        }
        if (nextStatus != null) {
          _status = nextStatus;
        }
        if (nextMessage != null) {
          _statusMessage = nextMessage;
        }
      });
    }

    if (notifyBackend) {
      await _api.stopFaceEnrollment();
    }
  }

  Future<void> _startRegistration() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() {
        _status = _EnrollStatus.failed;
        _statusMessage = 'Registration failed — please enter the person\'s full name first.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    final currentSession = ++_sessionToken;

    setState(() {
      _isStreaming = true;
      _currentFrame = null;
      _status = _EnrollStatus.positioning;
      _statusMessage = 'Starting Raspberry Pi camera stream...';
    });

    try {
      await _api.startFaceEnrollment();
      if (!mounted || currentSession != _sessionToken) return;

      setState(() {
        _status = _EnrollStatus.positioning;
        _statusMessage = 'Positioning face — please look directly at the door camera';
      });
    } catch (e) {
      if (!mounted || currentSession != _sessionToken) return;
      await _stopStream(
        notifyBackend: false,
        nextStatus: _EnrollStatus.failed,
        nextMessage: 'Registration failed — could not start camera stream ($e)',
      );
      return;
    }

    // 1. Live camera frame polling (~4 FPS over HTTPS)
    _frameTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (!_isStreaming || _fetchingFrame || currentSession != _sessionToken) return;
      _fetchingFrame = true;
      try {
        final bytes = await _api.fetchEnrollmentFrame();
        if (mounted && _isStreaming && currentSession == _sessionToken && bytes.isNotEmpty) {
          setState(() {
            _currentFrame = bytes;
          });
        }
      } catch (_) {
        // Ignore transient frame fetch hiccups while stream initializes
      } finally {
        _fetchingFrame = false;
      }
    });

    // 2. Automatic face detection & registration loop
    _scanTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) async {
      if (!_isStreaming || _scanningFace || currentSession != _sessionToken) return;
      _scanningFace = true;
      try {
        // Step 1: Detect if a single face is properly positioned
        final detectResp = await _api.scanAndEnrollFace(name: name, step: 'detect');
        if (!mounted || !_isStreaming || currentSession != _sessionToken) return;

        final detectState = detectResp['status']?.toString() ?? 'positioning';
        final detectMsg = detectResp['message']?.toString() ??
            'Positioning face — please look directly at the camera';

        if (detectState == 'positioning') {
          setState(() {
            _status = _EnrollStatus.positioning;
            _statusMessage = detectMsg;
          });
          return;
        }

        if (detectState == 'scanning') {
          setState(() {
            _status = _EnrollStatus.scanning;
            _statusMessage = detectMsg;
          });

          // Brief pause so user sees "Scanning..." status and holds steady
          await Future.delayed(const Duration(milliseconds: 450));
          if (!mounted || !_isStreaming || currentSession != _sessionToken) return;

          // Step 2: Extract 128-D face encoding and save to authorized_persons DB
          final regResp = await _api.scanAndEnrollFace(name: name, step: 'register');
          if (!mounted || !_isStreaming || currentSession != _sessionToken) return;

          final regState = regResp['status']?.toString() ?? 'positioning';
          final regMsg = regResp['message']?.toString() ?? '';

          if (regState == 'registered') {
            _nameCtrl.clear();
            await _stopStream(
              notifyBackend: false,
              nextStatus: _EnrollStatus.success,
              nextMessage: regMsg.isNotEmpty
                  ? regMsg
                  : 'Registration successful! $name is now an authorized person.',
              keepLastFrame: true,
            );
            return;
          } else {
            // Person moved during encoding; return to positioning
            setState(() {
              _status = _EnrollStatus.positioning;
              _statusMessage = regMsg.isNotEmpty
                  ? regMsg
                  : 'Positioning face — please hold still and look at the camera';
            });
          }
        }
      } catch (e) {
        if (!mounted || !_isStreaming || currentSession != _sessionToken) return;
        await _stopStream(
          notifyBackend: true,
          nextStatus: _EnrollStatus.failed,
          nextMessage: 'Registration failed — $e',
        );
      } finally {
        _scanningFace = false;
      }
    });

    // 3. Safety timeout after 45 seconds
    _timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (_isStreaming && currentSession == _sessionToken) {
        _stopStream(
          notifyBackend: true,
          nextStatus: _EnrollStatus.failed,
          nextMessage: 'Registration failed — timed out waiting for a clear face in front of the camera.',
        );
      }
    });
  }

  Future<void> _cancelRegistration() async {
    await _stopStream(
      notifyBackend: true,
      nextStatus: _EnrollStatus.idle,
      nextMessage: 'Registration cancelled — camera stream stopped.',
    );
  }

  Color _statusColor() {
    switch (_status) {
      case _EnrollStatus.positioning:
        return AppColors.warning;
      case _EnrollStatus.scanning:
        return AppColors.primary;
      case _EnrollStatus.success:
        return AppColors.success;
      case _EnrollStatus.failed:
        return AppColors.danger;
      case _EnrollStatus.idle:
        return AppColors.textSecondary;
    }
  }

  IconData _statusIcon() {
    switch (_status) {
      case _EnrollStatus.positioning:
        return Icons.center_focus_strong_rounded;
      case _EnrollStatus.scanning:
        return Icons.radar_rounded;
      case _EnrollStatus.success:
        return Icons.check_circle_rounded;
      case _EnrollStatus.failed:
        return Icons.error_outline_rounded;
      case _EnrollStatus.idle:
        return Icons.face_retouching_natural_rounded;
    }
  }

  String _statusTitle() {
    switch (_status) {
      case _EnrollStatus.positioning:
        return 'POSITIONING FACE';
      case _EnrollStatus.scanning:
        return 'SCANNING FACE';
      case _EnrollStatus.success:
        return 'REGISTRATION SUCCESSFUL';
      case _EnrollStatus.failed:
        return 'REGISTRATION FAILED';
      case _EnrollStatus.idle:
        return 'READY TO ENROLL';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Text(
                  'Enroll Face',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => context.go('/home/persons'),
                  icon: const Icon(Icons.people_alt_rounded, size: 18),
                  label: const Text('Authorized List'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Register a new authorized person using the live Raspberry Pi door camera.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Status Banner
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withOpacity(0.45), width: 1.3),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_statusIcon(), color: color, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusTitle(),
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusMessage,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_status == _EnrollStatus.scanning)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Live Camera Viewport
            Container(
              height: 240,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isStreaming ? color.withOpacity(0.7) : AppColors.cardBorder,
                  width: _isStreaming ? 2 : 1,
                ),
                boxShadow: _isStreaming
                    ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_currentFrame != null)
                      Image.memory(
                        _currentFrame!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    else if (_isStreaming)
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(AppColors.primary),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Connecting to Raspberry Pi camera stream...',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      )
                    else
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_off_outlined,
                            size: 52,
                            color: AppColors.textMuted,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Camera stream is off',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Press "Start Face Registration" to open live view',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),

                    // Face alignment guide overlay when streaming
                    if (_isStreaming) ...[
                      Center(
                        child: Container(
                          width: 160,
                          height: 195,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: color.withOpacity(0.85),
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.fiber_manual_record, color: AppColors.danger, size: 12),
                              SizedBox(width: 6),
                              Text(
                                'LIVE • RPi Camera',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Full Name Input Field
            TextField(
              controller: _nameCtrl,
              enabled: !_isStreaming,
              style: const TextStyle(color: AppColors.textPrimary),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Person\'s Full Name',
                hintText: 'e.g. John Doe',
                prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.cardBorder),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons: Start Face Registration / Cancel Registration
            if (!_isStreaming)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startRegistration,
                  icon: const Icon(Icons.camera_front_rounded, size: 22),
                  label: const Text(
                    'Start Face Registration',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _cancelRegistration,
                  icon: const Icon(Icons.cancel_outlined, color: AppColors.danger, size: 22),
                  label: const Text(
                    'Cancel Registration',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
