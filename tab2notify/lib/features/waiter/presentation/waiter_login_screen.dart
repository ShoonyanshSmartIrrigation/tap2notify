import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  @override
  void dispose() {
    _idController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _handleLogin(List<WaiterModel> registeredWaiters) async {
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
        ref.read(currentLoggedWaiterProvider.notifier).setWaiter(waiter);
        if (mounted) {
          context.go('/waiter-dashboard');
        }
      } else {
        // Check if waiter exists with different pin or not found
        final existsId = registeredWaiters.any(
          (w) => w.waiterId.toUpperCase() == id,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existsId
                  ? 'Incorrect PIN for Waiter $id. (Default PIN is 1234)'
                  : 'Waiter ID "$id" not found. Please contact Manager.',
            ),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
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
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero Waiter Badge
                  Center(
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
                  const SizedBox(height: 20),

                  Text(
                    'Waiter Floor Portal',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to access your assigned hotel tables',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Quick Select Chip Row for floor staff
                  if (registeredWaiters.isNotEmpty) ...[
                    const Text(
                      'Quick Pick Waiter ID:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: registeredWaiters.map((w) {
                        final isSelected = _idController.text == w.waiterId;
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
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.primary,
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
                              _pinController.text = w.passcode;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Waiter ID Field
                  TextFormField(
                    controller: _idController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Waiter ID',
                      hintText: 'e.g. W001',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Waiter ID is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // PIN Field
                  TextFormField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '4-Digit PIN',
                      hintText: 'Default PIN is 1234',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'PIN is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // Sign In Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 3,
                    ),
                    onPressed: _isLoading ? null : () => _handleLogin(registeredWaiters),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'ENTER WAITER DASHBOARD',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),

                  // Switch to Manager Login
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Floor Manager? ',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: Text(
                          'Manager Login',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
