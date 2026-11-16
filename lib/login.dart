import 'package:flutter/material.dart';
import 'db.dart';
import 'scope.dart';
import 'shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final u = TextEditingController(), p = TextEditingController();
  String? err = Session.notice; // mis. "akun terkunci" dari sesi sebelumnya
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    u.dispose();
    p.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      err = null;
    });

    try {
      final r = await Db.login(u.text.trim(), p.text);
      if (r == null) {
        if (mounted) {
          setState(() {
            err = 'Username atau password salah';
            _busy = false;
          });
        }
        return;
      }
      final lock = await Db.lockReason(r);
      if (lock != null) {
        if (mounted) {
          setState(() {
            err = lock;
            _busy = false;
          });
        }
        return;
      }
      Session.user = r;
      Session.notice = null;
      await Scope.load(); // mitra: daftar outlet miliknya
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const Shell()));
    } catch (e) {
      if (mounted) {
        setState(() {
          err = 'Terjadi kesalahan: $e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Ambient background glow (aksen merah lembut di atas)
          Positioned(
            top: -120,
            left: -80,
            right: -80,
            height: 360,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.6),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.8)),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.06),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo / Icon badge
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                cs.primary,
                                cs.secondary,
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.3),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/icon/logo.png',
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Kasir Outlet',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Outlet Makaroni • Point of Sale',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.outline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Input Username
                        TextField(
                          controller: u,
                          enabled: !_busy,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Input Password
                        TextField(
                          controller: p,
                          obscureText: _obscure,
                          enabled: !_busy,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _go(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),

                        // Error message
                        if (err != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9E8E6),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFE9B9B4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    size: 18, color: Color(0xFF97291F)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    err!,
                                    style: const TextStyle(
                                      color: Color(0xFF97291F),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Tombol Masuk
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            onPressed: _busy ? null : _go,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Masuk',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward_rounded,
                                          size: 18),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
