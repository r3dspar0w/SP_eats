import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

class ConsumerRegisterPage extends StatefulWidget {
  const ConsumerRegisterPage({super.key});

  @override
  State<ConsumerRegisterPage> createState() => _ConsumerRegisterPageState();
}

class _ConsumerRegisterPageState extends State<ConsumerRegisterPage> {
  static const Color kPink = Color(0xFFFF3D8D);
  static const Color kPinkSoft = Color(0xFFFFE3EF);
  static const Color kBorder = Color(0xFFEAEAEA);

  bool hidePw = true;
  bool hideConfirm = true;

  final emailCtrl = TextEditingController();
  final pwCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    emailCtrl.dispose();
    pwCtrl.dispose();
    confirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {int seconds = 2}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: Duration(seconds: seconds),
        ),
      );
  }

  bool _isValidEmail(String s) {
    final emailRegex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[A-Za-z]{2,}$');
    return emailRegex.hasMatch(s.trim());
  }

  Future<void> _onRegister() async {
    if (_loading) return;

    final email = emailCtrl.text.trim();
    final pw = pwCtrl.text;
    final confirm = confirmCtrl.text;

    if (email.isEmpty || pw.isEmpty || confirm.isEmpty) {
      _snack("Please fill in all fields");
      return;
    }

    if (!_isValidEmail(email)) {
      _snack("Please enter a valid email");
      return;
    }

    if (pw.length < 6) {
      _snack("Password must be at least 6 characters");
      return;
    }

    if (pw != confirm) {
      _snack("Passwords do not match");
      return;
    }

    setState(() => _loading = true);

    try {
      await AuthService().registerConsumer(email: email, password: pw);

      if (!mounted) return;
      _snack("Account created! Please login.", seconds: 2);

      Navigator.pushReplacementNamed(context, '/consumer_login');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'email-already-in-use') {
        _snack("Email already in use");
      } else if (e.code == 'weak-password') {
        _snack("Password is too weak");
      } else {
        _snack("Registration failed: ${e.message ?? e.code}");
      }
    } catch (e) {
      if (!mounted) return;
      _snack("Registration failed: $e");
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
            decoration: BoxDecoration(
              color: kPink,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.school_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Student/Staff Registration",
                  style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
                ),
                const SizedBox(height: 2),
                Text(
                  "Create an account to start ordering on SP Eats.",
                  style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black54),
                ),
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
                  Text(
                    "Register",
                    style: GoogleFonts.manrope(fontSize: 40, height: 1.05, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _lineDec(hint: "Email address", icon: Icons.email_outlined),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: pwCtrl,
                    obscureText: hidePw,
                    decoration: _lineDec(
                      hint: "Create a password",
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        onPressed: () => setState(() => hidePw = !hidePw),
                        icon: Icon(hidePw ? Icons.visibility_off : Icons.visibility, color: Colors.black45),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: hideConfirm,
                    decoration: _lineDec(
                      hint: "Confirm password",
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        onPressed: () => setState(() => hideConfirm = !hideConfirm),
                        icon: Icon(hideConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.black45),
                      ),
                    ),
                    onSubmitted: (_) => _onRegister(),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _onRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        _loading ? "Creating..." : "Register",
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pushReplacementNamed(context, '/consumer_login'),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black45),
                          children: [
                            const TextSpan(text: "Already have an account? "),
                            TextSpan(
                              text: "Login here",
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
