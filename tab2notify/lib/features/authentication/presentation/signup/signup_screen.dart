import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/errors/firebase_exception_mapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../auth_providers.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _inlineError;
  int _shakeTrigger = 0;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onFocusChange);
    _emailFocus.addListener(_onFocusChange);
    _phoneFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
    _confirmFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onFocusChange);
    _emailFocus.removeListener(_onFocusChange);
    _phoneFocus.removeListener(_onFocusChange);
    _passwordFocus.removeListener(_onFocusChange);
    _confirmFocus.removeListener(_onFocusChange);

    _nameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();

    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _handleSignup() async {
    if (_isLoading) return;

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _inlineError = null;
      });

      try {
        await ref.read(authRepositoryProvider).signUp(
              fullName: _nameController.text.trim(),
              email: _emailController.text.trim(),
              phone: _phoneController.text.trim(),
              password: _passwordController.text,
            );

        if (mounted) {
          HapticFeedback.mediumImpact();
          // Show sleek celebration dialog
          await _showSuccessCelebration(_nameController.text.trim());
          if (mounted) {
            context.go('/dashboard');
          }
        }
      } catch (e) {
        final message = FirebaseExceptionMapper.mapAuthException(e);
        if (mounted) {
          setState(() {
            _inlineError = message;
            _shakeTrigger++;
          });
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      setState(() => _shakeTrigger++);
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _showSuccessCelebration(String managerName) async {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Account Provisioned',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 250),
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
                  const SizedBox(height: 14),
                  Text(
                    'Account Created!',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    managerName.isNotEmpty
                        ? 'Welcome aboard, $managerName'
                        : 'Welcome to Tab2Notify',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Initializing your administrative dashboard...',
                    textAlign: TextAlign.center,
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

    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            // Soft ambient atmospheric glow accents
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

            // Top Navigation Bar
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Clean Back Button to Manager Login
                  InkWell(
                    onTap: () => context.go('/manager-login'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 14,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Manager Login',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Provisioning Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.domain_verification_rounded,
                          size: 13,
                          color: AppColors.primaryOrange,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'ONBOARDING',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: AppColors.primaryOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 72, 20, 28),
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
                            // 1. Header
                            _buildHeroHeader(theme, isDark),
                            const SizedBox(height: 22),

                            // 2. Inline Error Alert
                            if (_inlineError != null) ...[
                              _buildInlineErrorBanner(isDark),
                              const SizedBox(height: 18),
                            ],

                            // 3. Main Unified Registration Card
                            _buildRegistrationCard(theme, isDark),
                            const SizedBox(height: 20),

                            // 4. Footer Links
                            _buildFooterLinks(theme, isDark),
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
  // HERO HEADER
  // ==========================================
  Widget _buildHeroHeader(ThemeData theme, bool isDark) {
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFB923C),
                Color(0xFFEA580C),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA580C).withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF181818) : Colors.white,
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 36,
                  color: AppColors.primaryOrange,
                ),
              ),
            ],
          ),
        )
            .animate()
            .scale(duration: 400.ms, curve: Curves.easeOutBack)
            .fadeIn(duration: 350.ms),

        const SizedBox(height: 16),

        Text(
          'Manager Registration',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: 25,
            letterSpacing: -0.5,
          ),
        ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),

        const SizedBox(height: 6),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Provision a new administrative account to control restaurant tables, waiter allocations, and live call bells',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ).animate().fadeIn(delay: 150.ms),
      ],
    );
  }

  // ==========================================
  // INLINE ERROR BANNER
  // ==========================================
  Widget _buildInlineErrorBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1515) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: isDark ? 0.2 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFEF4444),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _inlineError ?? '',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color:
                    isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                height: 1.3,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            color: isDark ? Colors.white54 : Colors.black45,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _inlineError = null),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0);
  }

  // ==========================================
  // MAIN REGISTRATION CARD
  // ==========================================
  Widget _buildRegistrationCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section 1: Personal Details
          _buildSectionHeader(
            icon: Icons.badge_outlined,
            title: 'IDENTITY & PROFILE',
            isDark: isDark,
          ),
          const SizedBox(height: 14),

          _buildNameField(isDark),
          const SizedBox(height: 20),

          // Section 2: Contact Information
          _buildSectionHeader(
            icon: Icons.contact_mail_outlined,
            title: 'CONTACT & TELEMETRY',
            isDark: isDark,
          ),
          const SizedBox(height: 14),

          _buildEmailField(isDark),
          const SizedBox(height: 16),

          _buildPhoneField(isDark),
          const SizedBox(height: 20),

          // Section 3: Credentials
          _buildSectionHeader(
            icon: Icons.lock_outline_rounded,
            title: 'SECURITY CREDENTIALS',
            isDark: isDark,
          ),
          const SizedBox(height: 14),

          _buildPasswordField(isDark),
          const SizedBox(height: 16),

          _buildConfirmPasswordField(isDark),
          const SizedBox(height: 24),

          // Submit CTA
          _buildSubmitButton(),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.06, end: 0);
  }

  // Section Header Divider
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: AppColors.primaryOrange,
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: AppColors.primaryOrange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE2E8F0),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // FULL NAME FIELD
  // ==========================================
  Widget _buildNameField(bool isDark) {
    final hasFocus = _nameFocus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Full Name',
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
            controller: _nameController,
            focusNode: _nameFocus,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Full name is required';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: 'e.g. Alex Morgan',
              hintStyle: TextStyle(
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFFA0AEC0),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                Icons.person_outline_rounded,
                color: hasFocus
                    ? AppColors.primaryOrange
                    : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                size: 20,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // EMAIL FIELD
  // ==========================================
  Widget _buildEmailField(bool isDark) {
    final hasFocus = _emailFocus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email Address',
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
            controller: _emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Email is required';
              }
              final emailRegex = RegExp(
                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
              );
              if (!emailRegex.hasMatch(val.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: 'manager@restaurant.com',
              hintStyle: TextStyle(
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFFA0AEC0),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                Icons.alternate_email_rounded,
                color: hasFocus
                    ? AppColors.primaryOrange
                    : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                size: 20,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // MOBILE NUMBER FIELD (10 DIGITS)
  // ==========================================
  Widget _buildPhoneField(bool isDark) {
    final hasFocus = _phoneFocus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Mobile Number',
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '10 DIGITS',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
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
            controller: _phoneController,
            focusNode: _phoneFocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            maxLength: 10,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            autofillHints: const [AutofillHints.telephoneNumber],
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Mobile number is required';
              }
              final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
              if (digits.length != 10) {
                return 'Please enter a valid 10-digit mobile number';
              }
              return null;
            },
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Enter 10-digit mobile number',
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PASSWORD FIELD
  // ==========================================
  Widget _buildPasswordField(bool isDark) {
    final hasFocus = _passwordFocus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Password',
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
            Text(
              'MIN. 8 CHARS',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
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
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (_) {
              if (_confirmController.text.isNotEmpty) {
                setState(() {});
              }
            },
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Password is required';
              }
              if (val.length < 8) {
                return 'Password must be at least 8 characters';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: 'Enter your password (min. 8 characters)',
              hintStyle: TextStyle(
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFFA0AEC0),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                Icons.lock_outline_rounded,
                color: hasFocus
                    ? AppColors.primaryOrange
                    : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: hasFocus
                      ? AppColors.primaryOrange
                      : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                ),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // CONFIRM PASSWORD FIELD
  // ==========================================
  Widget _buildConfirmPasswordField(bool isDark) {
    final hasFocus = _confirmFocus.hasFocus;
    final isMatching = _confirmController.text.isNotEmpty &&
        _confirmController.text == _passwordController.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Confirm Password',
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
            if (_confirmController.text.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isMatching
                      ? (isDark
                          ? AppColors.successDark.withValues(alpha: 0.15)
                          : AppColors.success.withValues(alpha: 0.12))
                      : (isDark
                          ? Colors.amber.withValues(alpha: 0.15)
                          : Colors.amber.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMatching ? Icons.check_circle_rounded : Icons.pending_rounded,
                      size: 11,
                      color: isMatching
                          ? (isDark ? AppColors.successDark : AppColors.success)
                          : Colors.amber[800],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isMatching ? 'MATCHED' : 'DOES NOT MATCH',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: isMatching
                            ? (isDark
                                ? AppColors.successDark
                                : AppColors.success)
                            : Colors.amber[800],
                      ),
                    ),
                  ],
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
              color: isMatching
                  ? (isDark ? AppColors.successDark : AppColors.success)
                  : (hasFocus
                      ? AppColors.primaryOrange
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : const Color(0xFFE2E8F0))),
              width: hasFocus || isMatching ? 1.8 : 1.2,
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
            controller: _confirmController,
            focusNode: _confirmFocus,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => _handleSignup(),
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            validator: (val) {
              if (val != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: 'Re-enter your password',
              hintStyle: TextStyle(
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFFA0AEC0),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                Icons.lock_reset_rounded,
                color: hasFocus
                    ? AppColors.primaryOrange
                    : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: hasFocus
                      ? AppColors.primaryOrange
                      : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                ),
                tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PRIMARY CTA BUTTON
  // ==========================================
  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isLoading
              ? [
                  const Color(0xFFF97316).withValues(alpha: 0.7),
                  const Color(0xFFEA580C).withValues(alpha: 0.7),
                ]
              : [
                  const Color(0xFFFB923C),
                  const Color(0xFFEA580C),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEA580C).withValues(alpha: 0.38),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _handleSignup,
          child: Center(
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RepaintBoundary(
                        child: Lottie.asset(
                          'assets/animations/auth_loading.json',
                          width: 28,
                          height: 28,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'CREATING ACCOUNT...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'PROVISION MANAGER ACCOUNT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // FOOTER LINKS & NAVIGATION
  // ==========================================
  Widget _buildFooterLinks(ThemeData theme, bool isDark) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              'Already have a manager account?',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            InkWell(
              onTap: () => context.go('/manager-login'),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'Sign In',
                  style: TextStyle(
                    color: AppColors.primaryOrange,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.primaryOrange,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 250.ms);
  }
}
