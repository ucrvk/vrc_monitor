import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/services/auth_manager.dart';
import 'package:vrc_monitor/services/auth_vault.dart';
import 'package:vrc_monitor/services/cache_manager.dart';
import 'package:vrc_monitor/services/session_guard.dart';
import 'package:vrc_monitor/services/world_store.dart';
import 'package:vrc_monitor/widgets/main_shell.dart';

enum _TwoFactorMode { emailOtp, otpTotp }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.skipTokenAutoLogin = false});

  final bool skipTokenAutoLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _riskControlMessage = '登录流程被风控系统拦截，请检查您的安全设备(通常是邮件)来解决';
  static final RegExp _sixDigitCodePattern = RegExp(r'^\d{6}$');
  static final RegExp _recoveryCodePattern = RegExp(
    r'^[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}$',
  );

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  VrchatDart? _api;
  bool _isInitializing = true;
  bool _isLoading = false;
  bool _isAutoLoggingIn = false;
  bool _rememberPassword = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _initApi();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initApi() async {
    try {
      _rememberPassword = await AuthVault.instance.readRememberPassword();
      _usernameController.text = await AuthVault.instance.readUsername();
      if (_rememberPassword) {
        _passwordController.text = await AuthVault.instance.readPassword();
      } else {
        _passwordController.clear();
      }

      _api = VrchatDart(
        userAgent: const VrchatUserAgent(
          applicationName: 'vrc-monitor',
          version: '1.0.0',
          contactInfo: 'contact@vrc-monitor.app',
        ),
      );
      await AuthManager.instance.registerApi(_api!);

      if (widget.skipTokenAutoLogin) {
        return;
      }

      if (mounted) {
        setState(() {
          _isAutoLoggingIn = true;
          _message = '检测到会话，正在自动登录...';
        });
      }
      final user = await AuthManager.instance.tryAutoLogin(_api!);
      if (user != null) {
        AuthManager.instance.resetRecoveryState();
        SessionGuard.instance.resetLoginRequired();
        await _bootstrapAfterAuthenticated(_api!, user);
        return;
      }
      if (mounted) {
        setState(() {
          _isAutoLoggingIn = false;
          _message = null;
        });
      }
    } catch (e) {
      _setMessage('API 初始化失败: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _isAutoLoggingIn = false;
        });
      }
    }
  }

  Future<void> _login() async {
    final api = _api;
    if (api == null) {
      _setMessage('API 尚未初始化完成。', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final (loginSuccess, loginFailure) = await api.auth.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      ValidResponse<dynamic, dynamic>? twoFactorSuccess;

      if (loginSuccess == null) {
        _setMessage(_extractFailureText(loginFailure), isError: true);
        return;
      }

      final authResponse = loginSuccess.data;
      if (authResponse.requiresTwoFactorAuth) {
        final twoFactorMode = _resolveTwoFactorMode(authResponse);
        if (twoFactorMode == null) {
          _setMessage('当前账户的 2FA 类型暂不受支持。', isError: true);
          return;
        }

        final twoFactorCode = await _showTwoFactorDialog(twoFactorMode);
        if (!mounted) return;
        if (twoFactorCode == null || twoFactorCode.isEmpty) {
          _setMessage('已取消 OTP 验证。', isError: true);
          return;
        }

        final validationMessage = _validateTwoFactorCode(
          twoFactorMode,
          twoFactorCode,
        );
        if (validationMessage != null) {
          _setMessage(validationMessage, isError: true);
          return;
        }

        final normalizedCode = _normalizeTwoFactorCode(twoFactorCode);
        final (otpSuccess, otpFailure) = await _verifyTwoFactorCode(
          api,
          mode: twoFactorMode,
          code: normalizedCode,
        );
        if (otpSuccess == null) {
          _setMessage(_extractFailureText(otpFailure), isError: true);
          return;
        }

        twoFactorSuccess = otpSuccess;

        final (refreshSuccess, refreshFailure) = await api.auth.login();
        if (refreshSuccess == null) {
          _setMessage(_extractFailureText(refreshFailure), isError: true);
          return;
        }
        if (refreshSuccess.data.requiresTwoFactorAuth) {
          _setMessage('二次验证完成后仍需 2FA，请重试。', isError: true);
          return;
        }
      }

      final user = api.auth.currentUser;
      if (user == null) {
        _setMessage('登录失败：未获取到当前用户。', isError: true);
        return;
      }

      await _persistCredentials();
      await AuthManager.instance.captureSessionTokenFromResponses(
        api,
        primary: twoFactorSuccess,
        secondary: loginSuccess,
      );
      await AuthManager.instance.captureSessionTokenFromCurrentSession(api);
      AuthManager.instance.resetRecoveryState();
      SessionGuard.instance.resetLoginRequired();
      _setMessage('登录成功，正在预加载缓存...', isError: false);

      await _bootstrapAfterAuthenticated(api, user);
    } catch (e) {
      _setMessage('登录异常: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  _TwoFactorMode? _resolveTwoFactorMode(AuthResponse authResponse) {
    final types = authResponse.twoFactorAuthTypes.toSet();
    if (types.length == 1 && types.contains(TwoFactorAuthType.emailOtp)) {
      return _TwoFactorMode.emailOtp;
    }
    if (types.length == 2 &&
        types.contains(TwoFactorAuthType.otp) &&
        types.contains(TwoFactorAuthType.totp)) {
      return _TwoFactorMode.otpTotp;
    }
    return null;
  }

  String? _validateTwoFactorCode(_TwoFactorMode mode, String code) {
    if (mode == _TwoFactorMode.emailOtp) {
      return _sixDigitCodePattern.hasMatch(code) ? null : '请输入 6 位邮箱验证码。';
    }

    if (_sixDigitCodePattern.hasMatch(code) ||
        _recoveryCodePattern.hasMatch(code)) {
      return null;
    }
    return '请输入 6 位验证码，或形如 xxxx-xxxx 的 Recovery Code。';
  }

  String _normalizeTwoFactorCode(String code) {
    final trimmed = code.trim();
    if (_recoveryCodePattern.hasMatch(trimmed)) {
      return trimmed.toLowerCase();
    }
    return trimmed;
  }

  Future<(ValidResponse<dynamic, dynamic>?, InvalidResponse?)>
  _verifyTwoFactorCode(
    VrchatDart api, {
    required _TwoFactorMode mode,
    required String code,
  }) async {
    if (mode == _TwoFactorMode.emailOtp) {
      return api.rawApi
          .getAuthenticationApi()
          .verify2FAEmailCode(
            twoFactorEmailCode: TwoFactorEmailCode(code: code),
          )
          .validateVrc();
    }

    if (_sixDigitCodePattern.hasMatch(code)) {
      return api.auth.verify2fa(code);
    }

    if (_recoveryCodePattern.hasMatch(code)) {
      return api.rawApi
          .getAuthenticationApi()
          .verifyRecoveryCode(twoFactorAuthCode: TwoFactorAuthCode(code: code))
          .validateVrc();
    }

    return (null, null);
  }

  Future<String?> _showTwoFactorDialog(_TwoFactorMode mode) async {
    var otpCode = '';
    final isEmailOtp = mode == _TwoFactorMode.emailOtp;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isEmailOtp ? '输入邮箱验证码' : '输入 2FA 验证码'),
          content: TextField(
            autofocus: true,
            keyboardType: isEmailOtp
                ? TextInputType.number
                : TextInputType.text,
            onChanged: (value) => otpCode = value.trim(),
            decoration: InputDecoration(
              labelText: isEmailOtp ? '邮箱验证码' : '验证码 / Recovery Code',
              hintText: isEmailOtp ? '请输入 6 位邮箱验证码' : '请输入 123456 或 xxxx-xxxx',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(otpCode),
              child: const Text('提交'),
            ),
          ],
        );
      },
    );
  }

  void _setMessage(String msg, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _message = isError ? '错误: $msg' : msg;
    });
  }

  String _extractFailureText(InvalidResponse? failure) {
    if (failure == null) return '请求失败，未返回错误详情。';

    if (_isRiskControlFailure(failure)) {
      return _riskControlMessage;
    }

    final responseData = failure.response?.data;
    if (responseData is Map<String, dynamic>) {
      final errorMap = responseData['error'];
      if (errorMap is Map<String, dynamic> && errorMap['message'] != null) {
        return errorMap['message'].toString();
      }

      final message = responseData['message'];
      if (message != null) return message.toString();
    }

    return failure.error.toString();
  }

  bool _isRiskControlFailure(InvalidResponse failure) {
    return failure.response?.statusCode == 429;
  }

  Future<void> _bootstrapAfterAuthenticated(
    VrchatDart api,
    CurrentUser user,
  ) async {
    await CacheManager.instance.initialize(api: api, currentUser: user);
    await WorldStore.instance.initialize();

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MainShell(api: api, currentUser: user),
      ),
    );
  }

  Future<void> _persistCredentials() async {
    await AuthVault.instance.writeRememberPassword(_rememberPassword);
    await AuthVault.instance.writeUsername(_usernameController.text.trim());
    if (_rememberPassword) {
      await AuthVault.instance.writePassword(_passwordController.text);
    } else {
      await AuthVault.instance.clearPassword();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VRChat 登录')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _usernameController,
                  enabled: !_isLoading,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  enabled: !_isLoading,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
                CheckboxListTile(
                  value: _rememberPassword,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('记住密码'),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          setState(() {
                            _rememberPassword = value ?? false;
                          });
                        },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _isLoading || _isInitializing ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isInitializing ? '初始化中...' : '登录'),
                ),
                if (_isAutoLoggingIn) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: const [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('正在自动登录，请稍候...'),
                    ],
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _message!.startsWith('错误:')
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
