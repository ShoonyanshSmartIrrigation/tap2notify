import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/firebase_realtime_service.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
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

  bool _isFetchingWaiters = false;
  bool _isLoading = false;
  List<WaiterModel> _fetchedWaiters = [];
  bool _hasSearched = false;
  String? _lastSearchedPhone;

  // Brute-force protection state
  int _failedAttempts = 0;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  static const String _prefManagerPhoneKey = 'last_waiter_manager_phone';

  @override
  void initState() {
    super.initState();
    _loadSavedManagerPhone();
  }

  Future<void> _loadSavedManagerPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPhone = prefs.getString(_prefManagerPhoneKey);
      if (savedPhone != null && savedPhone.trim().isNotEmpty) {
        final digits = savedPhone.replaceAll(RegExp(r'[^0-9]'), '');
        final cleanPhone = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
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
    _managerPhoneController.dispose();
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

  Future<void> _fetchWaitersForManager(String phoneInput) async {
    final digits = phoneInput.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number.'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    setState(() {
      _isFetchingWaiters = true;
      _hasSearched = true;
      _lastSearchedPhone = digits;
    });

    try {
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
          if (!_fetchedWaiters.any((w) => w.waiterId == _idController.text.trim().toUpperCase())) {
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
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading waiters for manager: $e'),
            backgroundColor: const Color(0xFFE53935),
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

  void _handleLogin() async {
    if (_lockoutSeconds > 0) return;

    final managerDigits = _managerPhoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (managerDigits.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit manager mobile number.'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    if (!_hasSearched || _fetchedWaiters.isEmpty) {
      await _fetchWaitersForManager(managerDigits);
      if (_fetchedWaiters.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No waiters registered under Manager Mobile: $managerDigits'),
              backgroundColor: const Color(0xFFE53935),
            ),
          );
        }
        return;
      }
    }

    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final id = _idController.text.trim().toUpperCase();
      final pin = _pinController.text.trim();

      // Find matching waiter strictly under this manager's phone
      final match = _fetchedWaiters.where(
        (w) => w.waiterId.toUpperCase() == id && w.passcode == pin,
      );

      if (match.isNotEmpty) {
        final waiter = match.first.copyWith(
          managerPhone: FirebaseRealtimeService.sanitizePhone(managerDigits),
        );
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
          final existsId = _fetchedWaiters.any(
            (w) => w.waiterId.toUpperCase() == id,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  existsId
                      ? 'Incorrect PIN for Waiter $id ($remaining attempts remaining).'
                      : 'Waiter ID "$id" not found under Manager $managerDigits.',
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
                              color: theme.colorScheme.primary.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.person_pin_rounded,
                                color: theme.colorScheme.primary,
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
                        'Enter 10-digit Manager Mobile Number to load and select your Waiter ID',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 24),

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

                      // 1. STEP 1: Enter Manager Number Field
                      AppTextField(
                        label: 'Manager Mobile Number',
                        hint: 'Enter 10-digit mobile number',
                        prefixIcon: Icons.phone_android_rounded,
                        controller: _managerPhoneController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        onChanged: (val) {
                          if (val.trim().length == 10) {
                            _fetchWaitersForManager(val);
                          }
                        },
                        suffixIcon: IconButton(
                          icon: _isFetchingWaiters
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search_rounded),
                          tooltip: 'Fetch Staff',
                          onPressed: () => _fetchWaitersForManager(_managerPhoneController.text),
                        ),
                        onFieldSubmitted: (val) => _fetchWaitersForManager(val),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Manager Mobile Number is required';
                          }
                          final digits = val.replaceAll(RegExp(r'[^0-9]'), '');
                          if (digits.length != 10) {
                            return 'Please enter a valid 10-digit mobile number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 2. STEP 2: Fetch and Display Waiter IDs under that manager
                      if (_isFetchingWaiters) ...[
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Fetching staff under manager...',
                                  style: TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else if (_hasSearched && _fetchedWaiters.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No staff registered under "${_lastSearchedPhone ?? ""}". Check number or contact manager.',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else if (_fetchedWaiters.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Select Waiter ID (${_fetchedWaiters.length} Found):',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              'Manager: ${_lastSearchedPhone ?? ""}',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _fetchedWaiters.map((w) {
                            final isSelected = _idController.text.toUpperCase() == w.waiterId.toUpperCase();
                            return ChoiceChip(
                              avatar: CircleAvatar(
                                backgroundColor: isSelected
                                    ? Colors.white
                                    : theme.colorScheme.primary.withValues(alpha: 0.2),
                                child: Text(
                                  w.waiterId,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              label: Text('${w.waiterId} - ${w.name}'),
                              selected: isSelected,
                              selectedColor: theme.colorScheme.primary,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : null,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              onSelected: (selected) {
                                setState(() {
                                  _idController.text = w.waiterId;
                                  _pinController.clear();
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 3. STEP 3: Waiter ID Field
                      AppTextField(
                        label: 'Selected Waiter ID',
                        hint: 'e.g. W001, W002',
                        prefixIcon: Icons.badge_outlined,
                        controller: _idController,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please select or enter your Waiter ID';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 4. STEP 4: 4-Digit Password / PIN Field
                      AppTextField(
                        label: '4-Digit Password / PIN',
                        hint: 'Enter your 4-digit PIN',
                        prefixIcon: Icons.lock_outline,
                        controller: _pinController,
                        isPassword: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Password / PIN is required';
                          }
                          if (val.length < 4) {
                            return 'PIN must be at least 4 digits';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      // 5. STEP 5: Sign In Button
                      AppButton(
                        text: _lockoutSeconds > 0
                            ? 'LOCKED ($_lockoutSeconds s)'
                            : _idController.text.isNotEmpty
                                ? 'LOGIN AS ${_idController.text.toUpperCase()}'
                                : 'LOGIN TO DASHBOARD',
                        isLoading: _isLoading,
                        onPressed: (_lockoutSeconds > 0 || _isLoading)
                            ? () {}
                            : _handleLogin,
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

