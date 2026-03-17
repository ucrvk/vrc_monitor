import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/widgets/friends_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  VrchatDart? _api;
  bool _isInitializing = true;
  bool _isLoading = false;
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
      final prefs = await SharedPreferences.getInstance();
      _rememberPassword = prefs.getBool('remember_password') ?? false;
      _usernameController.text = prefs.getString('saved_username') ?? '';
      if (_rememberPassword) {
        _passwordController.text = prefs.getString('saved_password') ?? '';
      }

      final supportDir = await getApplicationSupportDirectory();
      final cookieDir = '${supportDir.path}/vrchat_cookies';
      _api = VrchatDart(
        userAgent: const VrchatUserAgent(
          applicationName: 'vrc-monitor',
          version: '1.0.0',
          contactInfo: 'contact@vrc-monitor.app',
        ),
        cookiePath: cookieDir,
      );
    } catch (e) {
      _setMessage('API 初始化失败: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
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

      if (loginSuccess == null) {
        _setMessage(_extractFailureText(loginFailure), isError: true);
        return;
      }

      final authResponse = loginSuccess.data;
      if (authResponse.requiresTwoFactorAuth) {
        final otpCode = await _showOtpDialog();
        if (!mounted) return;
        if (otpCode == null || otpCode.isEmpty) {
          _setMessage('已取消 OTP 验证。', isError: true);
          return;
        }

        final (otpSuccess, otpFailure) = await api.auth.verify2fa(otpCode);
        if (otpSuccess == null) {
          _setMessage(_extractFailureText(otpFailure), isError: true);
          return;
        }
      }

      final user = api.auth.currentUser;
      if (user == null) {
        _setMessage('登录失败：未获取到当前用户。', isError: true);
        return;
      }

      await _persistCredentials();

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => FriendsPage(api: api, currentUser: user),
        ),
      );
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

  Future<String?> _showOtpDialog() async {
    var otpCode = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('输入 OTP'),
          content: TextField(
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (value) => otpCode = value.trim(),
            decoration: const InputDecoration(
              labelText: '验证码',
              hintText: '请输入 OTP',
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

  Future<void> _persistCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_password', _rememberPassword);
    await prefs.setString('saved_username', _usernameController.text.trim());
    if (_rememberPassword) {
      await prefs.setString('saved_password', _passwordController.text);
    } else {
      await prefs.remove('saved_password');
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
