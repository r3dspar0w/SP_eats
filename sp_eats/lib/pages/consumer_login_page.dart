import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

class ConsumerLoginPage extends StatefulWidget {
  const ConsumerLoginPage({super.key});

  @override
  State<ConsumerLoginPage> createState() => _ConsumerLoginPageState();
}

class _ConsumerLoginPageState extends State<ConsumerLoginPage> {
  static const Color kPink = Color(0xFFFF3D8D);
  static const Color kPinkSoft = Color(0xFFFFE3EF);
  static const Color kBorder = Color(0xFFEAEAEA);

  bool hidePw = true;

  final usernameCtrl = TextEditingController();
  final pwCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    usernameCtrl.dispose();
    pwCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _onLogin() async {
    if (_loading) return;

    final email = usernameCtrl.text.trim();
    final p = pwCtrl.text;

    if (email.isEmpty || p.isEmpty) {
      _snack("Please fill in all fields");
      return;
    }

    setState(() => _loading = true);

    try {
      await AuthService().loginConsumer(email: email, password: p);
      if (!mounted) return;
      _snack("Login successful");
      Navigator.pushReplacementNamed(context, '/consumer_home');
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? "Login failed (${e.code})");
    } on UserProfileException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack("Login failed: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _topCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: kPinkSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: kPink, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.school_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Student/Staff Login", style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text("Sign in to continue on SP Eats.",
                    style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _lineDec({required String hint, required IconData icon, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black38),
      prefixIcon: Icon(icon, color: Colors.black45),
      suffixIcon: suffix,
      border: const UnderlineInputBorder(borderSide: BorderSide(color: kBorder)),
      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kBorder)),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPink, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  _topCard(),
                  const SizedBox(height: 24),
                  Text("Login", style: GoogleFonts.manrope(fontSize: 40, height: 1.05, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: usernameCtrl,
                    decoration: _lineDec(hint: "Enter your email", icon: Icons.email_outlined),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: pwCtrl,
                    obscureText: hidePw,
                    decoration: _lineDec(
                      hint: "Enter your password",
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        onPressed: () => setState(() => hidePw = !hidePw),
                        icon: Icon(hidePw ? Icons.visibility_off : Icons.visibility, color: Colors.black45),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _onLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(_loading ? "Signing in..." : "Login",
                          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pushReplacementNamed(context, '/consumer_register'),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black45),
                          children: [
                            const TextSpan(text: "Don't have an account? "),
                            TextSpan(
                              text: "Register here",
                              style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w900, color: kPink),
                            ),
                          ],
                        ),
                      ),
                    ),
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
