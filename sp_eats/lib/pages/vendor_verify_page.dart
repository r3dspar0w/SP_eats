import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';

class VendorVerifyPage extends StatefulWidget {
  const VendorVerifyPage({super.key});

  @override
  State<VendorVerifyPage> createState() => _VendorVerifyPageState();
}

class _VendorVerifyPageState extends State<VendorVerifyPage> {
  static const Color kPink = Color(0xFFFF3D8D);
  static const Color kPinkSoft = Color(0xFFFFE3EF);
  static const Color kBorder = Color(0xFFEAEAEA);

  final stallNoCtrl = TextEditingController();
  final stallNameCtrl = TextEditingController();

  static const List<String> _locations = [
    "Food Court 1",
    "Food Court 2",
    "Food Court 3",
    "Food Court 4",
    "Food Court 5",
    "Food Court 6",
    "Moberly Cafe",
    "Old Chang Kee",
  ];
  String? _selectedLocation;

  bool halalSelected = false;

  final ImagePicker _picker = ImagePicker();

  Uint8List? _stallPhotoBytes;
  Uint8List? _docBytes;
  Uint8List? _halalCertBytes;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _prefillIfExists();
  }

  @override
  void dispose() {
    stallNoCtrl.dispose();
    stallNameCtrl.dispose();
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

  Future<void> _prefillIfExists() async {
    try {
      final profile = await AuthService().getMyProfile();
      if (!mounted || profile == null) return;

      final status = profile['vendorStatus'] as String?;
      final submitted = (profile['vendorDetailsSubmitted'] as bool?) ?? false;
      if (status == 'APPROVED') {
        Navigator.pushReplacementNamed(context, '/vendor_home');
        return;
      }
      if (status == 'PENDING' && submitted) {
        Navigator.pushReplacementNamed(context, '/vendor_pending');
        return;
      }

      setState(() {
        stallNoCtrl.text = (profile['stallNo'] as String?) ?? '';
        stallNameCtrl.text = (profile['stallName'] as String?) ?? '';
        _selectedLocation = (profile['stallLocation'] as String?);
        halalSelected = (profile['isHalal'] as bool?) ?? false;
      });
    } catch (_) {}
  }

  InputDecoration _pillDec({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black54),
      prefixIcon: Icon(icon, color: Colors.black45),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kPink, width: 1.6),
      ),
    );
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
            child: const Icon(Icons.storefront, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Vendor Onboarding",
                  style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
                ),
                const SizedBox(height: 2),
                Text(
                  "Submit stall details for admin approval",
                  style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: kPinkSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: Icon(icon, color: kPink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ),
                    if (selected) const Icon(Icons.check_circle, color: kPink, size: 18),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: kPink,
              textStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            child: Text(selected ? "Uploaded" : "Upload"),
          ),
        ],
      ),
    );
  }

  Future<Uint8List?> _pickBytes({required String label}) async {
    if (_loading) return null;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 720,
    );
    if (picked == null) return null;

    try {
      final bytes = await picked.readAsBytes();
      
      if (bytes.length > 200 * 1024) {
        _snack("$label too large. Choose a smaller image.", seconds: 3);
        return null;
      }
      return bytes;
    } catch (_) {
      _snack("Failed to read image");
      return null;
    }
  }

  Future<void> _submit() async {
    if (_loading) return;

    final no = stallNoCtrl.text.trim();
    final name = stallNameCtrl.text.trim();
    final loc = _selectedLocation?.trim() ?? "";

    if (no.isEmpty || name.isEmpty || loc.isEmpty) {
      _snack("Please fill in stall details");
      return;
    }

    if (_stallPhotoBytes == null || _docBytes == null) {
      _snack("Please upload stall photo and verification document");
      return;
    }

    if (halalSelected && _halalCertBytes == null) {
      _snack("Please upload halal certificate");
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService().submitVendorDetailsWithImages(
        stallNo: no,
        stallName: name,
        stallLocation: loc,
        isHalal: halalSelected,
        stallPhotoBytes: _stallPhotoBytes,
        verificationDocBytes: _docBytes,
        halalCertBytes: _halalCertBytes,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/vendor_pending');
    } catch (_) {
      _snack("Submit failed (check Firestore rules / login)");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: _loading ? null : _prefillIfExists,
            icon: const Icon(Icons.refresh, color: Colors.black),
          ),
        ],
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
                  Text(
                    "Vendor Verification",
                    style: GoogleFonts.manrope(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                  const SizedBox(height: 12),
                  _topCard(),
                  const SizedBox(height: 18),

                  TextField(
                    controller: stallNoCtrl,
                    decoration: _pillDec(hint: "Stall Number", icon: Icons.confirmation_number_outlined),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stallNameCtrl,
                    decoration: _pillDec(hint: "Stall Name", icon: Icons.store_mall_directory_outlined),
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    key: ValueKey(_selectedLocation),
                    initialValue: _selectedLocation,
                    items: _locations
                        .map(
                          (loc) => DropdownMenuItem(
                            value: loc,
                            child: Text(
                              loc,
                              style: GoogleFonts.manrope(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.black87),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedLocation = v),
                    decoration: _pillDec(hint: "Stall Location", icon: Icons.location_on_outlined),
                  ),

                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Halal", style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(
                                halalSelected ? "Yes (halal-certified)" : "No (non-halal)",
                                style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: halalSelected,
                          onChanged: (v) {
                            setState(() {
                              halalSelected = v;
                              if (!v) _halalCertBytes = null;
                            });
                          },
                          activeThumbColor: Colors.white,
                          activeTrackColor: kPink,
                        ),
                      ],
                    ),
                  ),

                  if (halalSelected) ...[
                    const SizedBox(height: 12),
                    _uploadTile(
                      icon: Icons.verified_user_outlined,
                      title: "Halal certificate",
                      subtitle: "Upload halal certificate photo.",
                      selected: _halalCertBytes != null,
                      onTap: () async {
                        final b = await _pickBytes(label: "Halal certificate");
                        if (b == null) return;
                        if (!mounted) return;
                        setState(() => _halalCertBytes = b);
                        _snack("Halal certificate selected");
                      },
                    ),
                  ],

                  const SizedBox(height: 12),
                  _uploadTile(
                    icon: Icons.photo_camera_outlined,
                    title: "Stall photo",
                    subtitle: "Select a clear photo of your stall front.",
                    selected: _stallPhotoBytes != null,
                    onTap: () async {
                      final b = await _pickBytes(label: "Stall photo");
                      if (b == null) return;
                      if (!mounted) return;
                      setState(() => _stallPhotoBytes = b);
                      _snack("Stall photo selected");
                    },
                  ),

                  const SizedBox(height: 12),
                  _uploadTile(
                    icon: Icons.verified_outlined,
                    title: "Verification document",
                    subtitle: "Select proof (e.g. allocation or license).",
                    selected: _docBytes != null,
                    onTap: () async {
                      final b = await _pickBytes(label: "Verification document");
                      if (b == null) return;
                      if (!mounted) return;
                      setState(() => _docBytes = b);
                      _snack("Document selected");
                    },
                  ),

                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        _loading ? "Submitting..." : "Submit for approval",
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
