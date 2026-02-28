import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/mobile_bff_auth_api.dart';
import '../state/auth_scope.dart';

enum AuthMode {
  otpPhone, // Enter phone to send OTP (primary)
  otpVerify, // Enter OTP code
  otpRegister, // New user - enter name after OTP verified
  login, // Password login (fallback)
  register, // Password register (fallback)
}

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key, required AuthMode initialMode})
      : _mode = initialMode;

  final AuthMode _mode;

  static const double _cornerRadius = 10;

  static Future<void> showLogin(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final viewInsets = MediaQuery.viewInsetsOf(context);
        return AnimatedPadding(
          padding: viewInsets,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_cornerRadius),
            ),
            child: const AuthDialog(initialMode: AuthMode.otpPhone),
          ),
        );
      },
    );
  }

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _formKey = GlobalKey<FormState>();

  AuthMode _mode = AuthMode.otpPhone;
  bool _isSubmitting = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  String? _error;
  String? _otpChannel; // "whatsapp" or "sms"
  int? _resendCountdown;
  String _verifiedPhone = ''; // Phone number that was verified with OTP
  String _lastOtpCode = ''; // Last OTP code entered

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _otpFocusNode = FocusNode();

  Future<void> _focusField(FocusNode focusNode) async {
    if (!mounted) return;

    // Fully reset the input connection; some Android keyboards otherwise keep
    // the previous layout (e.g. phone keypad) even after focus changes.
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod('TextInput.hide');
    await SystemChannels.textInput.invokeMethod('TextInput.clearClient');

    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    FocusScope.of(context).requestFocus(focusNode);

    // Wait until the new field truly owns focus before showing the keyboard.
    for (var i = 0; i < 10; i++) {
      if (!mounted) return;
      if (focusNode.hasFocus) break;
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (!mounted) return;
    if (!focusNode.hasFocus) return;
    await SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  @override
  void initState() {
    super.initState();
    _mode = widget._mode;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusField(_phoneFocusNode);
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _confirmPasswordController.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  ({String firstName, String lastName}) _splitName(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return (firstName: '', lastName: '');
    final parts = normalized.split(' ');
    if (parts.length == 1) return (firstName: parts.first, lastName: '');
    return (
      firstName: parts.first,
      lastName: parts.sublist(1).join(' '),
    );
  }

  Future<void> _sendOtp() async {
    if (_isSubmitting) return;

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Please enter your phone number');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final auth = AuthScope.of(context);

    try {
      final result = await auth.sendOtp(phoneNumber: phone);

      if (!result.success) {
        setState(() {
          _error = result.message ?? 'Failed to send OTP';
          if (result.retryAfterSeconds != null) {
            _resendCountdown = result.retryAfterSeconds;
          }
        });
        return;
      }

      _verifiedPhone = phone;
      _otpChannel = result.channel;

      setState(() {
        _mode = AuthMode.otpVerify;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusField(_otpFocusNode);
      });
    } on AuthApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_isSubmitting) return;

    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty) {
      setState(() => _error = 'Please enter the OTP code');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final auth = AuthScope.of(context);

    try {
      final result = await auth.verifyOtp(
        phoneNumber: _verifiedPhone,
        otpCode: otpCode,
      );

      if (!result.success) {
        setState(() => _error = result.message ?? 'Invalid OTP');
        return;
      }

      if (result.requiresRegistration) {
        // New user - need to collect name
        _lastOtpCode = otpCode;
        setState(() => _mode = AuthMode.otpRegister);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusField(_nameFocusNode);
        });
        return;
      }

      // Existing user - logged in successfully
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod('TextInput.hide');
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AuthApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _registerWithOtp() async {
    if (_isSubmitting) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final auth = AuthScope.of(context);

    try {
      await auth.registerWithOtp(
        phoneNumber: _verifiedPhone,
        otpCode: _lastOtpCode,
        name: name,
      );

      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod('TextInput.hide');
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AuthApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
        final nameParts = _splitName(_nameController.text);
        await auth.register(
          firstName: nameParts.firstName,
          lastName: nameParts.lastName,
          phoneNumber: _phoneController.text.trim(),
          password: _passwordController.text,
        );
      }

      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod('TextInput.hide');
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusNode =
          _mode == AuthMode.register ? _nameFocusNode : _phoneFocusNode;
      _focusField(focusNode);
    });
  }

  void _switchToPasswordLogin() {
    setState(() {
      _error = null;
      _mode = AuthMode.login;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusField(_phoneFocusNode);
    });
  }

  void _switchToOtpLogin() {
    setState(() {
      _error = null;
      _mode = AuthMode.otpPhone;
      _otpController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusField(_phoneFocusNode);
    });
  }

  String get _title {
    switch (_mode) {
      case AuthMode.otpPhone:
        return 'Login with OTP';
      case AuthMode.otpVerify:
        return 'Enter OTP';
      case AuthMode.otpRegister:
        return 'Complete Registration';
      case AuthMode.login:
        return 'Login';
      case AuthMode.register:
        return 'Register';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _title;

    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AuthDialog._cornerRadius),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: const Color(0xFF0B6B63),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 22),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  16 + viewInsets.bottom,
                ),
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

                      // OTP Phone Entry Mode
                      if (_mode == AuthMode.otpPhone) ...[
                        const Text('Phone Number'),
                        const SizedBox(height: 6),
                        TextFormField(
                          key: const ValueKey('otp_phone_field'),
                          controller: _phoneController,
                          focusNode: _phoneFocusNode,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: 'Enter Phone Number',
                            hintStyle: TextStyle(color: Colors.black45),
                            prefixIcon: Icon(Icons.call_outlined),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _sendOtp,
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
                                : const Text('Send OTP'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed:
                              _isSubmitting ? null : _switchToPasswordLogin,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Use password instead'),
                        ),
                      ],

                      // OTP Verify Mode
                      if (_mode == AuthMode.otpVerify) ...[
                        if (_otpChannel != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'OTP sent via ${_otpChannel == 'whatsapp' ? 'WhatsApp' : 'SMS'} to $_verifiedPhone',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        const Text('Enter OTP'),
                        const SizedBox(height: 6),
                        TextFormField(
                          key: const ValueKey('otp_code_field'),
                          controller: _otpController,
                          focusNode: _otpFocusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          maxLength: 4,
                          decoration: const InputDecoration(
                            hintText: 'Enter 4-digit OTP',
                            hintStyle: TextStyle(color: Colors.black45),
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
                            isDense: true,
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _verifyOtp,
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
                                : const Text('Verify OTP'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _isSubmitting ? null : _sendOtp,
                              child: const Text('Resend OTP'),
                            ),
                            const SizedBox(width: 16),
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      setState(() {
                                        _mode = AuthMode.otpPhone;
                                        _otpController.clear();
                                      });
                                    },
                              child: const Text('Change Number'),
                            ),
                          ],
                        ),
                      ],

                      // OTP Register Mode (new user)
                      if (_mode == AuthMode.otpRegister) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Phone $_verifiedPhone verified! Enter your name to complete registration.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                        const Text('Name'),
                        const SizedBox(height: 6),
                        TextFormField(
                          key: const ValueKey('otp_register_name_field'),
                          controller: _nameController,
                          focusNode: _nameFocusNode,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: 'Enter your name',
                            hintStyle: TextStyle(color: Colors.black45),
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _registerWithOtp,
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
                                : const Text('Complete Registration'),
                          ),
                        ),
                      ],

                      // Password Login Mode
                      if (_mode == AuthMode.register) ...[
                        const Text('Name'),
                        const SizedBox(height: 6),
                        TextFormField(
                          key: const ValueKey('auth_name_field'),
                          controller: _nameController,
                          focusNode: _nameFocusNode,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Enter your name',
                            hintStyle: TextStyle(color: Colors.black45),
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
                            isDense: true,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_mode == AuthMode.login ||
                          _mode == AuthMode.register) ...[
                        const Text('Phone Number'),
                        const SizedBox(height: 6),
                        TextFormField(
                          key: const ValueKey('auth_phone_field'),
                          controller: _phoneController,
                          focusNode: _phoneFocusNode,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Enter Phone Number',
                            hintStyle: TextStyle(color: Colors.black45),
                            prefixIcon: Icon(Icons.call_outlined),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
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
                          key: const ValueKey('auth_password_field'),
                          controller: _passwordController,
                          obscureText: _hidePassword,
                          textInputAction: _mode == AuthMode.login
                              ? TextInputAction.done
                              : TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: 'Enter password',
                            hintStyle: const TextStyle(color: Colors.black45),
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
                            isDense: true,
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword),
                              icon: Icon(_hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              tooltip: _hidePassword
                                  ? 'Show password'
                                  : 'Hide password',
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Password is required';
                            }
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
                            key: const ValueKey('auth_confirm_password_field'),
                            controller: _confirmPasswordController,
                            obscureText: _hideConfirmPassword,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: 'Confirm password',
                              hintStyle: const TextStyle(color: Colors.black45),
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(10)),
                              ),
                              isDense: true,
                              suffixIcon: IconButton(
                                onPressed: () => setState(() =>
                                    _hideConfirmPassword =
                                        !_hideConfirmPassword),
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
                                : Text(_mode == AuthMode.login
                                    ? 'Login'
                                    : 'Register'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _isSubmitting ? null : _toggleMode,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                _mode == AuthMode.login
                                    ? "Don't have an account? Register"
                                    : 'Already have an account? Login',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _isSubmitting ? null : _switchToOtpLogin,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Login with OTP instead'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
