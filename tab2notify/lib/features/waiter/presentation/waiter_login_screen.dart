import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../service_requests/presentation/service_request_providers.dart';
import '../domain/waiter_model.dart';

class WaiterLoginScreen extends ConsumerStatefulWidget {
  const WaiterLoginScreen({super.key});

  @override
  ConsumerState<WaiterLoginScreen> createState() => _WaiterLoginScreenState();
}

class _WaiterLoginScreenState extends ConsumerState<WaiterLoginScreen> {
  final _idController = TextEditingController();
  final _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Brute-force protection state
  int _failedAttempts = 0;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void dispose() {
    _idController.dispose();
    _pinController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _startLockoutTimer() {
    setState(() {
      _lockoutSeconds = 30;
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
        });
      } else {
        setState(() {
          _lockoutSeconds--;
        });
      }
    });
  }

  void _promptManagerAccess() {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.admin_panel_settings_rounded,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Supervisor / Manager Access',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Restricted to authorized hotel management',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                AppButton(
                  text: 'PROCEED TO MANAGER LOGIN',
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/manager-login');
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleLogin(List<WaiterModel> registeredWaiters) async {
    if (_lockoutSeconds > 0) return;

    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final id = _idController.text.trim().toUpperCase();
      final pin = _pinController.text.trim();

      // Find matching waiter
      final match = registeredWaiters.where(
        (w) => w.waiterId.toUpperCase() == id && w.passcode == pin,
      );

      if (match.isNotEmpty) {
        final waiter = match.first;
        _failedAttempts = 0;
        await ref.read(currentLoggedWaiterProvider.notifier).setWaiter(waiter);
        if (mounted) {
          context.go('/waiter-dashboard');
        }
      } else {
        _failedAttempts++;
        if (_failedAttempts >= 5) {
          _startLockoutTimer();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Too many failed attempts. Login locked for 30 seconds.',
                ),
                backgroundColor: Color(0xFFE53935),
                duration: Duration(seconds: 4),
              ),
            );
          }
        } else {
          final remaining = 5 - _failedAttempts;
          final existsId = registeredWaiters.any(
            (w) => w.waiterId.toUpperCase() == id,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  existsId
                      ? 'Incorrect PIN for Waiter $id ($remaining attempts remaining).'
                      : 'Waiter ID "$id" not found. Please contact Manager.',
                ),
                backgroundColor: const Color(0xFFE53935),
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
    final waitersAsync = ref.watch(waitersStreamProvider);
    final registeredWaiters = waitersAsync.value ?? [];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hero Badge with Protected Hidden Long-Press Trigger for Managers
                      Center(
                        child: GestureDetector(
                          onLongPress: _promptManagerAccess,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.person_pin_rounded,
                                color: Colors.white,
                                size: 44,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Text(
                        'Floor Staff Portal',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign in to access your assigned tables',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Lockout Banner
                      if (_lockoutSeconds > 0) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFE53935).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.lock_clock_rounded,
                                color: Color(0xFFE53935),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Too many failed attempts. Try again in $_lockoutSeconds seconds.',
                                  style: const TextStyle(
                                    color: Color(0xFFE53935),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Quick Select Waiter ID Chips
                      if (registeredWaiters.isNotEmpty) ...[
                        const Text(
                          'Select Your Waiter ID:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: registeredWaiters.map((w) {
                            final isSelected = _idController.text.toUpperCase() == w.waiterId.toUpperCase();
                            return ActionChip(
                              avatar: CircleAvatar(
                                backgroundColor: isSelected
                                    ? Colors.white
                                    : theme.colorScheme.primary.withValues(alpha: 0.2),
                                child: Text(
                                  w.waiterId,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              label: Text(w.name),
                              backgroundColor: isSelected
                                  ? theme.colorScheme.primary
                                  : null,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : null,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              onPressed: () {
                                setState(() {
                                  _idController.text = w.waiterId;
                                  _pinController.clear();
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Waiter ID Input Field
                      AppTextField(
                        label: 'Waiter ID',
                        hint: 'e.g. W001',
                        prefixIcon: Icons.badge_outlined,
                        controller: _idController,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Waiter ID is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // PIN Field
                      AppTextField(
                        label: '4-Digit PIN',
                        hint: 'Enter your 4-digit PIN',
                        prefixIcon: Icons.lock_outline,
                        controller: _pinController,
                        isPassword: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(registeredWaiters),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'PIN is required';
                          }
                          if (val.length < 4) {
                            return 'PIN must be at least 4 digits';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      // Sign In Button
                      AppButton(
                        text: _lockoutSeconds > 0
                            ? 'LOCKED ($_lockoutSeconds s)'
                            : 'ENTER DASHBOARD',
                        isLoading: _isLoading,
                        onPressed: (_lockoutSeconds > 0 || _isLoading)
                            ? () {}
                            : () => _handleLogin(registeredWaiters),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
