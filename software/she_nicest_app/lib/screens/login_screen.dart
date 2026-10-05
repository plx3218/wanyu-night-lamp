import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// 登录页：老用户登录入口；新用户跳转 /register 建档
class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onLoggedIn, super.key});
  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await ApiService.login(username, password);
      await AuthService.save(session);
      widget.onLoggedIn();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = '连不上服务器，检查网络后再试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/erhai-blue-hour.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33102028), Color(0x22102028), Color(0xF014252B)],
                stops: [0, 0.35, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.moon.withValues(alpha: 0.35)),
                        color: AppColors.moon.withValues(alpha: 0.1),
                      ),
                      child: const Icon(Icons.bedtime_rounded, size: 38, color: AppColors.moon),
                    ),
                    const SizedBox(height: 18),
                    const Text('晚屿',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 6)),
                    const SizedBox(height: 8),
                    const Text('WANYU · 睡前陪伴',
                        style: TextStyle(fontSize: 12, color: AppColors.textTertiary, letterSpacing: 2)),
                    const SizedBox(height: 44),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                            decoration: _inputDecoration('用户名', Icons.person_outline_rounded),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _password,
                            obscureText: _obscure,
                            onSubmitted: (_) => _login(),
                            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                            decoration: _inputDecoration('密码', Icons.lock_outline_rounded).copyWith(
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 20,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.dusk),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(_error!,
                                      style: const TextStyle(
                                          fontSize: 13, color: AppColors.dusk, height: 1.4)),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              onPressed: _loading ? null : _login,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.moon,
                                foregroundColor: AppColors.ink,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.ink),
                                    )
                                  : const Text('进入晚屿', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('第一次使用？', style: TextStyle(fontSize: 14, color: AppColors.textTertiary)),
                        GestureDetector(
                          onTap: _loading
                              ? null
                              : () => Navigator.pushNamed(context, '/register'),
                          child: const Text(
                            '建立我的档案 →',
                            style: TextStyle(
                                fontSize: 14, color: AppColors.moon, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 15),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.moon.withValues(alpha: 0.5)),
      ),
      prefixIcon: Icon(icon, size: 20, color: AppColors.quiet),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    );
  }
}
