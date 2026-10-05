import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/firebase_realtime_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../service_requests/presentation/service_request_providers.dart';
import '../domain/waiter_model.dart';

class WaiterLoginScreen extends ConsumerStatefulWidget {
  const WaiterLoginScreen({super.key});

  @override
  ConsumerState<WaiterLoginScreen> createState() => _WaiterLoginScreenState();
}

class _WaiterLoginScreenState extends ConsumerState<WaiterLoginScreen> {
  final _managerPhoneController = TextEditingController();
  final _idController = TextEditingController();
  final _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final _managerPhoneFocus = FocusNode();
  final _idFocus = FocusNode();
  final _pinFocus = FocusNode();

  bool _isFetchingWaiters = false;
  bool _isLoading = false;
  List<WaiterModel> _fetchedWaiters = [];
  bool _hasSearched = false;
  String? _lastSearchedPhone;
  bool _obscurePin = true;
  String? _inlineError;

  // Brute-force protection state
  int _failedAttempts = 0;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;
  int _shakeTrigger = 0;

  static const String _prefManagerPhoneKey = 'last_waiter_manager_phone';

  @override
  void initState() {
    super.initState();
    _ensureAuthSession();
    _loadSavedManagerPhone();

    _managerPhoneFocus.addListener(_onFocusChange);
    _idFocus.addListener(_onFocusChange);
    _pinFocus.addListener(_onFocusChange);
  }

  Future<void> _ensureAuthSession() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint('[WAITER_LOGIN] Anonymous auth session active');
      }
    } catch (e) {
      debugPrint('[WAITER_LOGIN] Anonymous auth check/signIn attempt: $e');
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSavedManagerPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPhone = prefs.getString(_prefManagerPhoneKey);
      if (savedPhone != null && savedPhone.trim().isNotEmpty) {
        final digits = savedPhone.replaceAll(RegExp(r'[^0-9]'), '');
        final cleanPhone = digits.length >= 10
            ? digits.substring(digits.length - 10)
            : digits;
        if (cleanPhone.length == 10) {
          _managerPhoneController.text = cleanPhone;
          _fetchWaitersForManager(cleanPhone);
        }
      }
    } catch (e) {
      debugPrint('[WAITER_LOGIN] Error loading saved manager phone: $e');
    }
  }

  @override
  void dispose() {
    _managerPhoneFocus.removeListener(_onFocusChange);
    _idFocus.removeListener(_onFocusChange);
    _pinFocus.removeListener(_onFocusChange);

    _managerPhoneFocus.dispose();
    _idFocus.dispose();
    _pinFocus.dispose();

    _managerPhoneController.dispose();
    _idController.dispose();
    _pinController.dispose();
    _scrollController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _startLockoutTimer() {
    setState(() {
      _lockoutSeconds = 30;
      _inlineError =
          'Too many failed attempts. Terminal locked for 30 seconds.';
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockoutSeconds <= 1) {
        timer.cancel();
        setState(() {
          _lockoutSeconds = 0;
          _failedAttempts = 0;
          _inlineError = null;
        });
      } else {
        setState(() {
          _lockoutSeconds--;
        });
      }
    });
  }

  Future<void> _fetchWaitersForManager(String phoneInput) async {
    var digits = phoneInput.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }
    if (digits.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isFetchingWaiters = true;
      _hasSearched = true;
      _lastSearchedPhone = digits;
      _inlineError = null;
    });

    try {
      await _ensureAuthSession();
      final dbService = ref.read(firebaseRealtimeServiceProvider);
      final waiters = await dbService.fetchWaitersByPhone(digits);

      // Save valid manager phone for future ease of login
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefManagerPhoneKey, digits);

      if (mounted) {
        setState(() {
          _fetchedWaiters = waiters;
          _isFetchingWaiters = false;
          // If previous selection isn't in new list, clear it
          if (!_fetchedWaiters.any(
            (w) => w.waiterId == _idController.text.trim().toUpperCase(),
          )) {
            _idController.clear();
          }
        });
      }
    } catch (e) {
      debugPrint('[WAITER_LOGIN] Error fetching waiters: $e');
      if (mounted) {
        setState(() {
          _isFetchingWaiters = false;
          _fetchedWaiters = [];
          final errorMsg = e.toString().contains('permission-denied')
              ? 'Database access denied. Please verify Firebase security rules.'
              : 'Error loading staff roster for manager: $e';
          _inlineError = errorMsg;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading waiters for manager: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _promptManagerAccess() {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.primaryOrange,
                            AppColors.deepOrange,
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryOrange.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Supervisor / Manager Access',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Restricted to authorized restaurant management',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.65,
                              ),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryOrange, AppColors.deepOrange],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryOrange.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/manager-login');
                      },
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_open_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'PROCEED TO MANAGER LOGIN',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleLogin() async {
    // Prevent duplicate clicks while already processing or locked out
    if (_isLoading || _lockoutSeconds > 0) return;

    final rawManagerDigits = _managerPhoneController.text.trim().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final managerDigits = rawManagerDigits.length > 10
        ? rawManagerDigits.substring(rawManagerDigits.length - 10)
        : rawManagerDigits;
    if (managerDigits.length != 10) {
      setState(() {
        _inlineError = 'Please enter a valid 10-digit manager mobile number.';
        _shakeTrigger++;
      });
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit manager mobile number.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!_hasSearched || _fetchedWaiters.isEmpty) {
      await _fetchWaitersForManager(managerDigits);
      if (_fetchedWaiters.isEmpty) {
        if (mounted) {
          setState(() {
            _inlineError =
                'No staff registered under Manager Mobile: $managerDigits';
            _shakeTrigger++;
          });
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No waiters registered under Manager Mobile: $managerDigits',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _inlineError = null;
      });

      await _ensureAuthSession();
      final id = _idController.text.trim().toUpperCase();
      final pin = _pinController.text.trim();

      // Secure Server-Side Waiter PIN Verification
      final dbService = ref.read(firebaseRealtimeServiceProvider);
      final authenticatedWaiter = await dbService.authenticateWaiter(
        managerPhone: managerDigits,
        waiterId: id,
        passcode: pin,
      );

      if (authenticatedWaiter != null) {
        final waiter = authenticatedWaiter.copyWith(
          managerPhone: FirebaseRealtimeService.sanitizePhone(managerDigits),
        );
        _failedAttempts = 0;

        // Ensure active auth session for RTDB tenant access
        if (FirebaseAuth.instance.currentUser == null) {
          try {
            await FirebaseAuth.instance.signInAnonymously();
          } catch (_) {}
        }

        await ref.read(currentLoggedWaiterProvider.notifier).setWaiter(waiter);

        // Register device FCM token for this waiter with session isolation
        await FCMService().syncWaiterSession(
          waiter.managerPhone,
          waiter.waiterId,
        );

        if (mounted) {
          HapticFeedback.mediumImpact();
          // Display production-ready success celebration dialog before routing
          showGeneralDialog(
            context: context,
            barrierDismissible: false,
            barrierLabel: 'Login Success',
            barrierColor: Colors.black.withValues(alpha: 0.55),
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (ctx, anim1, anim2) {
              final isDark = Theme.of(ctx).brightness == Brightness.dark;
              return Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryOrange.withValues(alpha: 0.3),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RepaintBoundary(
                          child: Lottie.asset(
                            'assets/animations/auth_success.json',
                            width: 100,
                            height: 100,
                            repeat: false,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Authentication Verified!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Welcome, ${waiter.name} (${waiter.waiterId})',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryOrange,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Connecting to restaurant floor...',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );

          // Allow celebration animation to smoothly complete
          await Future.delayed(const Duration(milliseconds: 1500));

          if (mounted) {
            if (Navigator.of(context, rootNavigator: true).canPop()) {
              Navigator.of(context, rootNavigator: true).pop();
            }
            context.go('/waiter-dashboard');
          }
        }
      } else {
        _failedAttempts++;
        _pinController.clear();
        HapticFeedback.heavyImpact();

        if (_failedAttempts >= 5) {
          _startLockoutTimer();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Too many failed attempts. Terminal locked for 30 seconds.',
                ),
                backgroundColor: AppColors.error,
                duration: Duration(seconds: 4),
              ),
            );
          }
        } else {
          final remaining = 5 - _failedAttempts;
          final existsId = _fetchedWaiters.any(
            (w) => w.waiterId.toUpperCase() == id,
          );

          final errorMsg = existsId
              ? 'Incorrect PIN for Waiter $id ($remaining attempts remaining).'
              : 'Waiter ID "$id" not found under Manager $managerDigits.';

          setState(() {
            _inlineError = errorMsg;
            _shakeTrigger++;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMsg),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            // Soft ambient atmospheric glows
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryOrange.withValues(
                    alpha: isDark ? 0.08 : 0.09,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -50,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.deepOrange.withValues(
                    alpha: isDark ? 0.06 : 0.07,
                  ),
                ),
              ),
            ),

            // Scrollable terminal content
            Center(
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Form(
                      key: _formKey,
                      child: Animate(
                        key: ValueKey(_shakeTrigger),
                        effects: _shakeTrigger > 0
                            ? [
                                const ShakeEffect(
                                  duration: Duration(milliseconds: 380),
                                  hz: 4,
                                  offset: Offset(8, 0),
                                ),
                              ]
                            : [],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Elegant Brand Header & Lottie
                            _buildBrandHeader(theme, isDark),
                            const SizedBox(height: 20),

                            // 2. Lockout Countdown Alert
                            if (_lockoutSeconds > 0) ...[
                              _buildLockoutBanner(isDark),
                              const SizedBox(height: 18),
                            ],

                            // 3. Inline Animated Error Alert
                            if (_inlineError != null &&
                                _lockoutSeconds == 0) ...[
                              _buildInlineErrorBanner(isDark),
                              const SizedBox(height: 16),
                            ],

                            // 4. Main Unified Login Card
                            _buildUnifiedLoginCard(theme, isDark),
                            const SizedBox(height: 18),

                            // 5. Manager Portal Footer Link
                            _buildSupervisorFooter(theme, isDark),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // BRAND HEADER & LOTTIE HERO
  // ==========================================
  Widget _buildBrandHeader(ThemeData theme, bool isDark) {
    return Column(
      children: [
        // Lottie Illustration Box (Crisp, self-contained, interactive)
        GestureDetector(
              onLongPress: _promptManagerAccess,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryOrange.withValues(alpha: 0.14),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: RepaintBoundary(
                  child: Lottie.asset(
                    'assets/animations/restaurant_service.json',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            )
            .animate()
            .fadeIn(duration: 500.ms, curve: Curves.easeOut)
            .scale(
              begin: const Offset(0.9, 0.9),
              end: const Offset(1, 1),
              duration: 500.ms,
              curve: Curves.easeOutBack,
            ),

        const SizedBox(height: 14),

        // Screen Heading & Subtitle
        Text(
              'Floor Staff Portal',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 24,
                letterSpacing: -0.4,
              ),
            )
            .animate()
            .fadeIn(delay: 100.ms, duration: 350.ms)
            .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),

        const SizedBox(height: 5),

        Text(
              'Connect with manager phone to select your ID & begin service shift',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
                height: 1.35,
              ),
            )
            .animate()
            .fadeIn(delay: 150.ms, duration: 350.ms)
            .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
      ],
    );
  }

  // ==========================================
  // UNIFIED MAIN CARD COMPONENT
  // ==========================================
  Widget _buildUnifiedLoginCard(ThemeData theme, bool isDark) {
    return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.35)
                    : const Color(0xFF64748B).withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // STEP 1: Manager Phone Field
              _buildManagerPhoneField(theme, isDark),
              const SizedBox(height: 16),

              // STEP 2: Staff Roster Selector
              _buildStaffRosterSection(theme, isDark),

              // STEP 3: Waiter ID Field
              _buildWaiterIdField(theme, isDark),
              const SizedBox(height: 16),

              // STEP 4: Security PIN Field
              _buildPinField(theme, isDark),
              const SizedBox(height: 24),

              // STEP 5: Animated Elevated Login Button
              _buildLoginButton(theme, isDark),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 200.ms, duration: 450.ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }

  // ==========================================
  // STEP 1: MANAGER PHONE FIELD
  // ==========================================
  Widget _buildManagerPhoneField(ThemeData theme, bool isDark) {
    final hasFocus = _managerPhoneFocus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Manager Mobile Number',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: hasFocus
                      ? AppColors.primaryOrange
                      : (isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF334155)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: hasFocus
                    ? AppColors.primaryOrange.withValues(alpha: 0.15)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'STEP 1',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: hasFocus
                      ? AppColors.primaryOrange
                      : (isDark ? Colors.grey[400] : const Color(0xFF64748B)),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Animated Focus Border Container
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161616) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasFocus
                  ? AppColors.primaryOrange
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : const Color(0xFFE2E8F0)),
              width: hasFocus ? 1.8 : 1.2,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: AppColors.primaryOrange.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: TextFormField(
            controller: _managerPhoneController,
            focusNode: _managerPhoneFocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            maxLength: 10,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(14),
            ],
            onChanged: (val) {
              setState(() => _inlineError = null);
              final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
              if (digits.length >= 10) {
                final clean = digits.substring(digits.length - 10);
                if (_managerPhoneController.text != clean) {
                  _managerPhoneController.value = TextEditingValue(
                    text: clean,
                    selection: TextSelection.collapsed(offset: clean.length),
                  );
                }
                _fetchWaitersForManager(clean);
              }
            },
            onFieldSubmitted: (val) => _fetchWaitersForManager(val),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Manager Mobile Number is required';
              }
              final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
              final clean = digits.length > 10
                  ? digits.substring(digits.length - 10)
                  : digits;
              if (clean.length != 10) {
                return 'Please enter a valid 10-digit mobile number';
              }
              return null;
            },
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Enter 10-digit manager number',
              hintStyle: TextStyle(
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFFA0AEC0),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                Icons.phone_android_rounded,
                color: hasFocus
                    ? AppColors.primaryOrange
                    : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                size: 20,
              ),
              suffixIcon: _isFetchingWaiters
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(13.0),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryOrange,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_managerPhoneController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            color: isDark ? Colors.white38 : Colors.black38,
                            tooltip: 'Clear',
                            onPressed: () {
                              setState(() {
                                _managerPhoneController.clear();
                                _fetchedWaiters = [];
                                _hasSearched = false;
                                _idController.clear();
                                _pinController.clear();
                              });
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.search_rounded),
                          color: AppColors.primaryOrange,
                          tooltip: 'Fetch Staff',
                          onPressed: () => _fetchWaitersForManager(
                            _managerPhoneController.text,
                          ),
                        ),
                      ],
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 2: STAFF ROSTER SELECTOR
  // ==========================================
  Widget _buildStaffRosterSection(ThemeData theme, bool isDark) {
    if (_isFetchingWaiters) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primaryOrange.withValues(
            alpha: isDark ? 0.08 : 0.05,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primaryOrange.withValues(alpha: 0.2),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryOrange,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Fetching floor staff under manager...',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryOrange,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasSearched && _fetchedWaiters.isEmpty) {
      return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: isDark ? 0.14 : 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No staff registered under "${_lastSearchedPhone ?? ""}". Please contact manager.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
          .animate()
          .fadeIn(duration: 250.ms)
          .scale(begin: const Offset(0.97, 0.97), end: const Offset(1, 1));
    }

    if (_fetchedWaiters.isNotEmpty) {
      return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161616) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people_alt_outlined,
                            size: 16,
                            color: AppColors.primaryOrange,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Select Waiter ID (${_fetchedWaiters.length} Found)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.grey[300]
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Mgr: ${_lastSearchedPhone ?? ""}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _fetchedWaiters.map((w) {
                    final isSelected =
                        _idController.text.toUpperCase() ==
                        w.waiterId.toUpperCase();
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _idController.text = w.waiterId;
                          _pinController.clear();
                          _inlineError = null;
                        });
                        // Automatically transition focus to PIN input
                        _pinFocus.requestFocus();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [
                                    AppColors.primaryOrange,
                                    AppColors.deepOrange,
                                  ],
                                )
                              : null,
                          color: isSelected
                              ? null
                              : (isDark
                                    ? const Color(0xFF222222)
                                    : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.deepOrange
                                : (isDark
                                      ? Colors.white12
                                      : const Color(0xFFCBD5E1)),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primaryOrange.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: isSelected
                                  ? Colors.white
                                  : AppColors.primaryOrange.withValues(
                                      alpha: 0.18,
                                    ),
                              child: Text(
                                w.waiterId.length >= 2
                                    ? w.waiterId.substring(
                                        w.waiterId.length - 2,
                                      )
                                    : w.waiterId,
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primaryOrange,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '${w.waiterId} • ${w.name}',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B)),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          )
          .animate()
          .fadeIn(duration: 250.ms)
          .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1));
    }

    return const SizedBox.shrink();
  }

  // ==========================================
  // STEP 3: WAITER ID FIELD
  // ==========================================
  Widget _buildWaiterIdField(ThemeData theme, bool isDark) {
    final hasFocus = _idFocus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Selected Waiter ID',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: hasFocus
                      ? AppColors.primaryOrange
                      : (isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF334155)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: hasFocus
                    ? AppColors.primaryOrange.withValues(alpha: 0.15)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'STEP 2',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: hasFocus
                      ? AppColors.primaryOrange
                      : (isDark ? Colors.grey[400] : const Color(0xFF64748B)),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161616) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasFocus
                  ? AppColors.primaryOrange
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : const Color(0xFFE2E8F0)),
              width: hasFocus ? 1.8 : 1.2,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: AppColors.primaryOrange.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: TextFormField(
            controller: _idController,
            focusNode: _idFocus,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
              letterSpacing: 1,
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please select or enter your Waiter ID';
              }
              return null;
            },
            decoration: InputDecoration(
              counterText: '',
              hintText: 'e.g. W001, W002',
              hintStyle: TextStyle(
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFFA0AEC0),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
              prefixIcon: Icon(
                Icons.badge_rounded,
                color: hasFocus
                    ? AppColors.primaryOrange
                    : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 4: SECURITY PIN FIELD
  // ==========================================
  Widget _buildPinField(ThemeData theme, bool isDark) {
    final hasFocus = _pinFocus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Security Passcode / PIN',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: hasFocus
                      ? AppColors.primaryOrange
                      : (isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF334155)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: hasFocus
                    ? AppColors.primaryOrange.withValues(alpha: 0.15)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'STEP 3',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: hasFocus
                      ? AppColors.primaryOrange
                      : (isDark ? Colors.grey[400] : const Color(0xFF64748B)),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161616) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasFocus
                  ? AppColors.primaryOrange
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : const Color(0xFFE2E8F0)),
              width: hasFocus ? 1.8 : 1.2,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: AppColors.primaryOrange.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: TextFormField(
            controller: _pinController,
            focusNode: _pinFocus,
            obscureText: _obscurePin,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onFieldSubmitted: (_) => _handleLogin(),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 3,
            ),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Passcode / PIN is required';
              }
              if (val.length < 4) {
                return 'PIN must be at least 4 digits';
              }
              return null;
            },
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••',
              hintStyle: TextStyle(
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFFA0AEC0),
                fontSize: 16,
                letterSpacing: 3,
              ),
              prefixIcon: Icon(
                Icons.lock_rounded,
                color: hasFocus
                    ? AppColors.primaryOrange
                    : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePin
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                  size: 20,
                ),
                tooltip: _obscurePin ? 'Show PIN' : 'Hide PIN',
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 5: ELEVATED ANIMATED LOGIN BUTTON
  // ==========================================
  Widget _buildLoginButton(ThemeData theme, bool isDark) {
    final isLocked = _lockoutSeconds > 0;
    final isReady = !isLocked && !_isLoading;

    final String buttonLabel = isLocked
        ? 'LOCKED ($_lockoutSeconds s)'
        : _isLoading
        ? 'VERIFYING CREDENTIALS...'
        : _idController.text.isNotEmpty
        ? 'LOGIN AS ${_idController.text.toUpperCase()}'
        : 'START FLOOR SHIFT';

    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: isLocked
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryOrange, AppColors.deepOrange],
              ),
        color: isLocked
            ? (isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1))
            : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isReady
            ? [
                BoxShadow(
                  color: AppColors.primaryOrange.withValues(alpha: 0.38),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isReady ? _handleLogin : null,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _isLoading
                  ? Row(
                      key: const ValueKey('loading_state'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RepaintBoundary(
                          child: Lottie.asset(
                            'assets/animations/auth_loading.json',
                            height: 24,
                            width: 34,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          buttonLabel,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      key: ValueKey(buttonLabel),
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            buttonLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: isLocked
                                  ? (isDark ? Colors.white38 : Colors.black38)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // LOCKOUT BANNER
  // ==========================================
  Widget _buildLockoutBanner(bool isDark) {
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: isDark ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.error.withValues(alpha: 0.4),
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.lock_clock_rounded,
                color: AppColors.error,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Security Lockout: Terminal locked for $_lockoutSeconds seconds.',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1));
  }

  // ==========================================
  // INLINE ERROR BANNER WITH LOTTIE ICON
  // ==========================================
  Widget _buildInlineErrorBanner(bool isDark) {
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: isDark ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.error.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              RepaintBoundary(
                child: Lottie.asset(
                  'assets/animations/auth_error.json',
                  width: 24,
                  height: 24,
                  repeat: false,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _inlineError ?? '',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.error,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => setState(() => _inlineError = null),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: -0.1, end: 0, curve: Curves.easeOutCubic);
  }

  // ==========================================
  // SUPERVISOR FOOTER
  // ==========================================
  Widget _buildSupervisorFooter(ThemeData theme, bool isDark) {
    return Center(
      child: TextButton.icon(
        onPressed: _promptManagerAccess,
        icon: const Icon(
          Icons.shield_outlined,
          size: 16,
          color: AppColors.primaryOrange,
        ),
        label: Text(
          'Restaurant Manager / Supervisor Portal',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
