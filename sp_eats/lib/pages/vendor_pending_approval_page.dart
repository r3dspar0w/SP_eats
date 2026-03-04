import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';

class VendorPendingApprovalPage extends StatefulWidget {
  const VendorPendingApprovalPage({super.key});

  @override
  State<VendorPendingApprovalPage> createState() => _VendorPendingApprovalPageState();
}

class _VendorPendingApprovalPageState extends State<VendorPendingApprovalPage> {
  static const Color kPink = Color(0xFFFF3D8D);
  static const Color kPinkSoft = Color(0xFFFFE3EF);
  static const Color kBorder = Color(0xFFEAEAEA);

  bool _loading = false;

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

  Future<void> _logoutToLogin() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await AuthService().logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/vendor_login', (_) => false);
    } catch (_) {
      _snack("Logout failed");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _card() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kPinkSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Submitted ✅",
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your vendor application has been sent for review.\n\n"
            "Our admin team will verify your details soon. "
            "You will receive an email once your account is approved.",
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Pending Approval",
                    style: GoogleFonts.manrope(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _card(),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _logoutToLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        _loading ? "Please wait..." : "Back to Vendor Login",
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w900),
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
