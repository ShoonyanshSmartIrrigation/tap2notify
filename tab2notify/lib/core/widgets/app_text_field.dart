import 'package:flutter/material.dart';

class AppTextField extends StatefulWidget {
  final String label;
  final String hint;
  final IconData prefixIcon;
  final TextEditingController? controller;
  final bool isPassword;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const AppTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    this.controller,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.isPassword;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          obscureText: _obscureText,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          autofillHints: widget.autofillHints,
          textCapitalization: widget.textCapitalization,
          validator: widget.validator,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF64748B)
                  : const Color(0xFFA0AEC0),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Icon(widget.prefixIcon, color: theme.colorScheme.primary),
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscureText
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureText = !_obscureText),
                  )
                : null,
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}
