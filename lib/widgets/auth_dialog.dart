import 'package:flutter/material.dart';

import '../services/mobile_bff_auth_api.dart';
import '../state/auth_scope.dart';

enum AuthMode {
  login,
  register,
}

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key, required AuthMode initialMode})
      : _mode = initialMode;

  final AuthMode _mode;

  static Future<void> showLogin(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: AuthDialog(initialMode: AuthMode.login),
      ),
    );
  }

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _formKey = GlobalKey<FormState>();

  AuthMode _mode = AuthMode.login;
  bool _isSubmitting = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  String? _error;

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _mode = widget._mode;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _error = null);

    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk) return;

    setState(() => _isSubmitting = true);

    final auth = AuthScope.of(context);

    try {
      if (_mode == AuthMode.login) {
        await auth.login(
          phoneOrEmail: _phoneController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await auth.register(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          password: _passwordController.text,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } on AuthApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _error = null;
      _mode = _mode == AuthMode.login ? AuthMode.register : AuthMode.login;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _mode == AuthMode.login ? 'Login' : 'Register';

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: const Color(0xFF0B6B63),
            child: Row(
              children: [
                const Icon(Icons.person_outline, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed:
                      _isSubmitting ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_mode == AuthMode.register) ...[
                    const Text('First Name'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _firstNameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Enter your first name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'First name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Last Name'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _lastNameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Enter your last name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text('Phone Number'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'e.g., +1234567890 or 1234567890',
                      prefixIcon: Icon(Icons.call_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Phone number is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Password'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _hidePassword,
                    textInputAction: _mode == AuthMode.login
                        ? TextInputAction.done
                        : TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'Enter password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(_hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        tooltip:
                            _hidePassword ? 'Show password' : 'Hide password',
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (_mode == AuthMode.register && v.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  if (_mode == AuthMode.register) ...[
                    const SizedBox(height: 12),
                    const Text('Confirm Password'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _hideConfirmPassword,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: 'Confirm password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          onPressed: () => setState(() =>
                              _hideConfirmPassword = !_hideConfirmPassword),
                          icon: Icon(_hideConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          tooltip: _hideConfirmPassword
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Confirm your password';
                        }
                        if (v != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B6B63),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _mode == AuthMode.login ? 'Login' : 'Register'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isSubmitting ? null : _toggleMode,
                    child: Text(
                      _mode == AuthMode.login
                          ? "Don't have an account?  Register"
                          : 'Already have an account?  Login',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
