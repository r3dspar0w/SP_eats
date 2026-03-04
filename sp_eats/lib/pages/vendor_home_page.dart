import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'welcome_page.dart';

const String kHfApiKey = "hi";
const String kHfImageModel = "stabilityai/stable-diffusion-xl-base-1.0";
const String kHfProxyUrl = "";

class VendorHomePage extends StatefulWidget {
  const VendorHomePage({super.key});

  @override
  State<VendorHomePage> createState() => _VendorHomePageState();
}

class _VendorHomePageState extends State<VendorHomePage> {
  static const Color kPink = Color(0xFFFF3D8D);

  int index = 0;

  String? _stallTag;
  String _queueStatus = "NO_QUEUE";

  List<VendorMenuItem> items = [];

  String? paynowQrUrl;
  final ImagePicker _picker = ImagePicker();
  final Set<String> _assigningDisplayNo = <String>{};

  late final List<PromoPoster> promos;
  final TextEditingController _promoPromptCtrl = TextEditingController();
  bool _promoGenerating = false;
  String? _promoPreviewB64;

  static const List<String> allowedTags = [
    "Vegetarian",
    "Western",
    "Indian",
    "Thai",
    "Chinese",
    "Korean",
    "Japanese",
    "Drinks",
    "Dessert",
  ];

  static const List<String> allowedQueue = [
    "VERY_BUSY",
    "MODERATE",
    "NO_QUEUE",
  ];

  @override
  void initState() {
    super.initState();
    promos = [const PromoPoster.asset("assets/sampleposter.png")];
    _loadMenuItems();
  }

  @override
  void dispose() {
    _promoPromptCtrl.dispose();
    super.dispose();
  }

  Future<String?> _generatePromoPosterB64(String prompt) async {
    final useProxy = kHfProxyUrl.trim().isNotEmpty;
    final hasApiKey =
        kHfApiKey.trim().isNotEmpty &&
        !kHfApiKey.contains("PASTE_YOUR_HF_API_KEY");

    if (!useProxy && !hasApiKey) {
      _snack("Set your Hugging Face API key (or start the local proxy).");
      return null;
    }

    if (useProxy) {
      try {
        final resp = await http
            .post(
              Uri.parse(kHfProxyUrl),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({"prompt": prompt}),
            )
            .timeout(const Duration(seconds: 90));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw Exception("Proxy error ${resp.statusCode}: ${resp.body}");
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final b64 = _normalizeAnyB64((data["imageB64"] as String?) ?? "");
        return b64.isEmpty ? null : b64;
      } catch (_) {
        if (!hasApiKey) {
          throw Exception(
            "Local image generator is offline. Start server/hf_proxy.js or set a valid Hugging Face API key.",
          );
        }
      }
    }

    final uri = Uri.parse(
      "https://router.huggingface.co/hf-inference/models/$kHfImageModel",
    );
    final body = jsonEncode({
      "inputs": prompt,
      // Favor prompt adherence over image quality.
      "parameters": {"guidance_scale": 9.0, "num_inference_steps": 20},
      "options": {"wait_for_model": true},
    });

    final resp = await http
        .post(
          uri,
          headers: {
            "Authorization": "Bearer $kHfApiKey",
            "Content-Type": "application/json",
            "Accept": "image/png",
          },
          body: body,
        )
        .timeout(const Duration(seconds: 90));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception("Hugging Face error ${resp.statusCode}: ${resp.body}");
    }

    final contentType = resp.headers["content-type"] ?? "";
    if (contentType.startsWith("image/")) {
      return _normalizeAnyB64(base64Encode(resp.bodyBytes));
    }

    try {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data.containsKey("error")) {
        throw Exception("Hugging Face error: ${data["error"]}");
      }
    } catch (_) {}

    return null;
  }

  Future<void> _generatePromoPreview({
    required String prompt,
    required String vendorUid,
    required String fcId,
  }) async {
    if (fcId.trim().isEmpty) {
      _snack("Set your foodcourt number first");
      return;
    }
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      _snack("Enter a prompt first");
      return;
    }

    setState(() => _promoGenerating = true);
    try {
      final b64 = await _generatePromoPosterB64(trimmed);
      if (b64 == null || b64.isEmpty) {
        _snack("Image generation failed");
        return;
      }
      if (!mounted) return;
      setState(() => _promoPreviewB64 = b64);
      _snack(
        "Poster generated. Tap 'Add this poster to your promos' to save it.",
      );
    } catch (e) {
      _snack("Generate failed: $e");
    } finally {
      if (mounted) setState(() => _promoGenerating = false);
    }
  }

  Future<void> _addPreviewPromoToDb({
    required String vendorUid,
    required String fcId,
  }) async {
    final preview = _normalizeAnyB64(_promoPreviewB64 ?? "");
    if (fcId.trim().isEmpty) {
      _snack("Set your foodcourt first");
      return;
    }
    if (preview.isEmpty) {
      _snack("Generate a poster first");
      return;
    }

    try {
      final optimized = _optimizePosterForFirestore(preview);
      if (optimized == null || optimized.isEmpty) {
        _snack("Generated poster format is invalid");
        return;
      }
      await _savePromoB64(b64: optimized, vendorUid: vendorUid, fcId: fcId);
      if (!mounted) return;
      setState(() {
        _promoPreviewB64 = null;
        _promoPromptCtrl.clear();
      });
      _snack("Poster added to promos");
    } catch (e) {
      _snack("Failed to save poster: $e");
    }
  }

  Future<void> _savePromoB64({
    required String b64,
    required String vendorUid,
    required String fcId,
  }) async {
    final normalized = _normalizeAnyB64(b64);
    if (normalized.isEmpty) {
      _snack("Invalid image format");
      return;
    }
    if (normalized.length > 900000) {
      _snack("Image too large for Firestore. Please try another image.");
      return;
    }

    final promosRef = _stallPromosCollection(fcId: fcId, vendorUid: vendorUid);
    final promoId = promosRef.doc().id;
    final promoRef = promosRef.doc(promoId);

    final payload = <String, dynamic>{
      'imageB64': normalized,
      'createdAt': FieldValue.serverTimestamp(),
      'fcId': fcId,
      'vendorUid': vendorUid,
    };

    await promoRef.set(payload);
    await _trimVendorPromosToFive(promosRef: promosRef);
  }

  Future<void> _trimVendorPromosToFive({
    required CollectionReference<Map<String, dynamic>> promosRef,
  }) async {
    final snap = await promosRef
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();
    if (snap.docs.length <= 5) return;

    final toDelete = snap.docs.skip(5).toList();
    final batch = FirebaseFirestore.instance.batch();

    for (final d in toDelete) {
      batch.delete(d.reference);
    }

    await batch.commit();
  }

  Future<void> _uploadPromoFromGallery({required String fcId}) async {
    if (fcId.trim().isEmpty) {
      _snack("Set your foodcourt number first");
      return;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 65,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final b64 = _normalizeAnyB64(base64Encode(bytes));
    if (!mounted) return;
    setState(() => _promoPreviewB64 = b64);
    _snack("Poster selected. Tap 'Add this poster to your promos' to save.");
  }

  String _normalizeAnyB64(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return "";
    if (s.startsWith("b64:")) s = s.substring(4);
    if (s.startsWith("data:")) {
      final comma = s.indexOf(',');
      if (comma != -1) s = s.substring(comma + 1);
    }
    s = s.replaceAll(RegExp(r"\s+"), "");
    return s;
  }

  String? _optimizePosterForFirestore(String rawB64) {
    final b64 = _normalizeAnyB64(rawB64);
    if (b64.isEmpty) return null;
    Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return null;
    }

    if (b64.length <= 900000) return b64;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    img.Image current = decoded;
    const widths = [1024, 896, 768, 640, 512];
    const qualities = [85, 75, 65, 55, 45];

    for (final w in widths) {
      if (current.width > w) {
        current = img.copyResize(current, width: w);
      }
      for (final q in qualities) {
        final jpg = img.encodeJpg(current, quality: q);
        final out = base64Encode(jpg);
        if (out.length <= 900000) return out;
      }
    }
    return null;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  String _prettyQueue(String s) {
    switch (s) {
      case "NO_QUEUE":
        return "No queue";
      case "MODERATE":
        return "Moderate";
      case "VERY_BUSY":
        return "Very busy";
      default:
        return s;
    }
  }

  String? _foodcourtIdFromVendorData(Map<String, dynamic> vendorData) {
    final explicitFcId = (vendorData['foodCourtId'] as String?)?.trim();
    if (explicitFcId != null && explicitFcId.isNotEmpty) return explicitFcId;

    final foodcourtNo = (vendorData['foodcourtNo'] as num?)?.toInt();
    if (foodcourtNo != null && foodcourtNo >= 1 && foodcourtNo <= 6) {
      return 'fc$foodcourtNo';
    }

    final loc = (vendorData['stallLocation'] as String?)?.toLowerCase() ?? "";
    final compact = loc.replaceAll(RegExp(r'[\s_-]+'), '');
    if (compact.contains('foodcourt1') || compact.contains('fc1')) return 'fc1';
    if (compact.contains('foodcourt2') || compact.contains('fc2')) return 'fc2';
    if (compact.contains('foodcourt3') || compact.contains('fc3')) return 'fc3';
    if (compact.contains('foodcourt4') || compact.contains('fc4')) return 'fc4';
    if (compact.contains('foodcourt5') || compact.contains('fc5')) return 'fc5';
    if (compact.contains('foodcourt6') || compact.contains('fc6')) return 'fc6';
    return null;
  }

  CollectionReference<Map<String, dynamic>> _stallMenuCollection({
    required String fcId,
    required String vendorUid,
  }) {
    return FirebaseFirestore.instance
        .collection('foodcourts')
        .doc(fcId)
        .collection('stalls')
        .doc(vendorUid)
        .collection('menuItems');
  }

  CollectionReference<Map<String, dynamic>> _stallPromosCollection({
    required String fcId,
    required String vendorUid,
  }) {
    return FirebaseFirestore.instance
        .collection('foodcourts')
        .doc(fcId)
        .collection('stalls')
        .doc(vendorUid)
        .collection('promos');
  }

  Future<void> _syncVendorIntoFoodcourtStalls({
    required String vendorUid,
    required Map<String, dynamic> vendorData,
  }) async {
    final fcId = _foodcourtIdFromVendorData(vendorData);
    if (fcId == null) return;

    final doc = FirebaseFirestore.instance
        .collection('foodcourts')
        .doc(fcId)
        .collection('stalls')
        .doc(vendorUid);

    await doc.set({
      'vendorUid': vendorUid,
      'uid': vendorUid,
      'stallName': (vendorData['stallName'] as String?) ?? "Your stall",
      'stallNo': (vendorData['stallNo'] as String?) ?? "-",
      'stallLocation': (vendorData['stallLocation'] as String?) ?? "-",
      'foodcourtNo': (vendorData['foodcourtNo'] as num?)?.toInt(),
      'stallTag': vendorData['stallTag'],
      'queueStatus': vendorData['queueStatus'] ?? "NO_QUEUE",
      'isHalal': vendorData['isHalal'] ?? false,
      'paynowQrUrl': vendorData['paynowQrUrl'],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  List<VendorMenuItem> _buildSampleMenuItems() {
    return [
      VendorMenuItem(
        id: "sample_item",
        name: "Edit this to create your first menu item",
        subtitle: "Tap to edit name, price, image and sold out",
        price: 0.00,
        badge: "",
        imageUrl: "",
        optionGroups: const [],
        soldOut: false,
      ),
    ];
  }

  Future<void> _loadMenuItems() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    try {
      final vendorSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();
      final fcId = _foodcourtIdFromVendorData(vendorSnap.data() ?? {});
      if (fcId == null) {
        setState(() => items = _buildSampleMenuItems());
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('foodcourts')
          .doc(fcId)
          .collection('stalls')
          .doc(u.uid)
          .collection('menuItems')
          .get();

      if (snap.docs.isEmpty) {
        setState(() => items = _buildSampleMenuItems());
        await _saveMenuItemsToDb();
        return;
      }

      final loaded = snap.docs
          .map((d) => _menuItemFromMap(d.id, d.data()))
          .toList();
      setState(() => items = loaded);
    } catch (_) {
      if (!mounted) return;
      setState(() => items = _buildSampleMenuItems());
    }
  }

  Future<void> _saveMenuItemsToDb() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final vendorSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .get();
    final fcId = _foodcourtIdFromVendorData(vendorSnap.data() ?? {});
    if (fcId == null) return;

    final fcCol = _stallMenuCollection(fcId: fcId, vendorUid: u.uid);
    final fcSnap = await fcCol.get();

    final fcBatch = FirebaseFirestore.instance.batch();
    final ids = items.map((e) => e.id).toSet();
    for (final doc in fcSnap.docs) {
      if (!ids.contains(doc.id)) fcBatch.delete(doc.reference);
    }
    for (final item in items) {
      fcBatch.set(
        fcCol.doc(item.id),
        _menuItemToMap(item),
        SetOptions(merge: true),
      );
    }

    await fcBatch.commit();
  }

  VendorMenuItem _menuItemFromMap(String id, Map<String, dynamic> data) {
    final rawGroups = (data['optionGroups'] as List?) ?? [];
    final groups = rawGroups.map((g) {
      final gm = (g as Map).cast<String, dynamic>();
      final rawChoices = (gm['choices'] as List?) ?? [];
      final choices = rawChoices.map((c) {
        final cm = (c as Map).cast<String, dynamic>();
        return OptionChoice(
          label: (cm['label'] as String?) ?? "",
          extraPrice: (cm['extraPrice'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
      return OptionGroup(
        title: (gm['title'] as String?) ?? "",
        maxSelect: (gm['maxSelect'] as num?)?.toInt() ?? 1,
        choices: choices,
      );
    }).toList();

    return VendorMenuItem(
      id: id,
      name: (data['name'] as String?) ?? "Untitled item",
      subtitle: (data['subtitle'] as String?) ?? "",
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      badge: (data['badge'] as String?) ?? "",
      imageUrl: ((data['imageUrl'] as String?)?.trim().isNotEmpty ?? false)
          ? (data['imageUrl'] as String)
          : ((data['imagePath'] as String?) ?? ""),
      optionGroups: groups,
      soldOut: (data['soldOut'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> _menuItemToMap(VendorMenuItem item) {
    return {
      'name': item.name,
      'subtitle': item.subtitle,
      'price': item.price,
      'badge': item.badge,
      'imageUrl': item.imageUrl,
      'soldOut': item.soldOut,
      'optionGroups': item.optionGroups
          .map(
            (g) => {
              'title': g.title,
              'maxSelect': g.maxSelect,
              'choices': g.choices
                  .map((c) => {'label': c.label, 'extraPrice': c.extraPrice})
                  .toList(),
            },
          )
          .toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _saveVendorSettings({
    required String? stallTag,
    required String queueStatus,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    if (stallTag != null &&
        stallTag.trim().isNotEmpty &&
        !allowedTags.contains(stallTag)) {
      _snack("Invalid tag");
      return;
    }
    if (!allowedQueue.contains(queueStatus)) {
      _snack("Invalid queue status");
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
      'stallTag': stallTag,
      'queueStatus': queueStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final vendorSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .get();
    await _syncVendorIntoFoodcourtStalls(
      vendorUid: u.uid,
      vendorData: vendorSnap.data() ?? {},
    );

    if (!mounted) return;
    setState(() {
      _stallTag = stallTag;
      _queueStatus = queueStatus;
    });
    _snack("Settings saved");
  }

  Future<void> _pickAndUploadQr() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 900,
    );
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > 850 * 1024) {
        _snack("QR too large. Choose a smaller image.");
        return;
      }
      final qrValue = "b64:${base64Encode(bytes)}";

      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
        'paynowQrUrl': qrValue,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final vendorSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();
      await _syncVendorIntoFoodcourtStalls(
        vendorUid: u.uid,
        vendorData: vendorSnap.data() ?? {},
      );

      if (!mounted) return;
      setState(() => paynowQrUrl = qrValue);
      _snack("QR uploaded");
    } catch (e) {
      _snack("Upload failed: ${e.toString()}");
    }
  }

  Future<void> _pickAndUploadStallPhoto() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 900,
    );
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > 850 * 1024) {
        _snack("Image too large. Choose a smaller image.");
        return;
      }
      final imageB64 = base64Encode(bytes);

      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
        'stallPhotoB64': imageB64,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final vendorSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();
      final fcId = _foodcourtIdFromVendorData(vendorSnap.data() ?? {});
      if (fcId != null) {
        await FirebaseFirestore.instance
            .collection('foodcourts')
            .doc(fcId)
            .collection('stalls')
            .doc(u.uid)
            .set({
              'stallPhotoB64': imageB64,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }

      _snack("Stall image updated");
    } catch (e) {
      _snack("Failed to update stall image: ${e.toString()}");
    }
  }

  Future<int> allocateDisplayNoForVendor(String vendorUid) async {
    final metaRef = FirebaseFirestore.instance
        .collection('users')
        .doc(vendorUid)
        .collection('meta')
        .doc('orderCounter');

    return FirebaseFirestore.instance.runTransaction<int>((tx) async {
      final snap = await tx.get(metaRef);
      final current = (snap.data()?['next'] as num?)?.toInt() ?? 1;

      final allocated = current;
      final next = allocated + 1;

      tx.set(metaRef, {
        'next': next,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return allocated;
    });
  }

  Future<void> _ensureOrderDisplayNo({
    required String vendorUid,
    required String orderDocId,
    required Map<String, dynamic> data,
  }) async {
    final currentDisplayNo = (data['displayNo'] as num?)?.toInt() ?? 0;
    if (currentDisplayNo > 0) return;
    if (_assigningDisplayNo.contains(orderDocId)) return;
    _assigningDisplayNo.add(orderDocId);

    try {
      final orderRef = FirebaseFirestore.instance
          .collection('orders')
          .doc(orderDocId);
      final metaRef = FirebaseFirestore.instance
          .collection('users')
          .doc(vendorUid)
          .collection('meta')
          .doc('orderCounter');

      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
        final orderSnap = await tx.get(orderRef);
        final orderData = orderSnap.data();
        final existingNo = (orderData?['displayNo'] as num?)?.toInt() ?? 0;
        if (existingNo > 0) return;

        final metaSnap = await tx.get(metaRef);
        final current = (metaSnap.data()?['next'] as num?)?.toInt() ?? 1;
        final allocated = current;

        tx.set(metaRef, {
          'next': allocated + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(orderRef, {
          'displayNo': allocated,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (_) {
    } finally {
      _assigningDisplayNo.remove(orderDocId);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream(String vendorUid) {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('stallUid', isEqualTo: vendorUid)
        .snapshots();
  }

  Future<void> _setOrderReady({
    required String vendorUid,
    required String orderDocId,
    required bool isReady,
  }) async {
    final ref = FirebaseFirestore.instance.collection('orders').doc(orderDocId);
    await ref.set({
      'status': isReady ? 'READY' : 'PLACED',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Uint8List? _tryDecodeB64(String? b64) {
    if (b64 == null) return null;
    final s = b64.trim();
    if (s.isEmpty) return null;
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  Widget _stallAvatarFromB64(String? b64, {double radius = 22}) {
    final bytes = _tryDecodeB64(b64);
    if (bytes == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.black.withOpacity(0.06),
        child: Icon(Icons.storefront, color: Colors.black87, size: radius),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: MemoryImage(bytes),
      backgroundColor: Colors.black.withOpacity(0.06),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    final userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data!.data() ?? {};
        final role = (data['role'] as String?) ?? '';
        final vendorStatus = (data['vendorStatus'] as String?) ?? '';
        final fcId = _foodcourtIdFromVendorData(data);

        if (role != 'vendor') {
          return const Scaffold(
            body: Center(child: Text("This account is not a vendor")),
          );
        }

        if (vendorStatus != 'APPROVED') {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hourglass_top, size: 46),
                      const SizedBox(height: 10),
                      Text(
                        "Pending approval",
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Your vendor account is not approved yet.\nOnce approved, login again and you’ll be redirected here.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await FirebaseAuth.instance.signOut();
                            if (!mounted) return;
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const WelcomePage(),
                              ),
                              (r) => false,
                            );
                          },
                          icon: const Icon(Icons.logout),
                          label: Text(
                            "Logout",
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final stallDocStream = (fcId == null)
            ? null
            : FirebaseFirestore.instance
                  .collection('foodcourts')
                  .doc(fcId)
                  .collection('stalls')
                  .doc(u.uid)
                  .snapshots();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: stallDocStream,
          builder: (context, stallSnap) {
            final stallData = stallSnap.data?.data() ?? <String, dynamic>{};
            final merged = <String, dynamic>{...data, ...stallData};

            final email = (merged['email'] as String?) ?? (u.email ?? "");
            final stallName = (merged['stallName'] as String?) ?? "Your stall";
            final stallNo =
                (merged['stallNo'] as String?) ??
                (merged['stallNumber'] as String?) ??
                "-";
            final stallLocation =
                (merged['stallLocation'] as String?) ??
                (merged['location'] as String?) ??
                "-";
            final foodcourtNo =
                (merged['foodcourtNo'] as num?)?.toInt() ??
                (fcId != null && fcId.startsWith('fc')
                    ? int.tryParse(fcId.substring(2))
                    : null);
            final isHalal =
                (merged['isHalal'] as bool?) ??
                (merged['halalStatus'] as bool?) ??
                false;

            final stallPhotoB64 = (merged['stallPhotoB64'] as String?);
            paynowQrUrl = (merged['paynowQrUrl'] as String?) ?? paynowQrUrl;

            _stallTag = (merged['stallTag'] as String?);
            _queueStatus = (merged['queueStatus'] as String?) ?? "NO_QUEUE";

            final pages = [
              VendorHomeTab(
                items: items,
                vendorEmail: email,
                stallName: stallName,
                stallNo: stallNo,
                stallLocation: stallLocation,
                foodcourtNo: foodcourtNo,
                isHalal: isHalal,
                stallTag: _stallTag,
                queueStatus: _queueStatus,
                stallPhotoB64: stallPhotoB64,
                onTapMenuItem: (item) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VendorMenuItemDetailPage(
                        item: item,
                        onItemSaved: (updated) async {
                          final idx = items.indexWhere(
                            (e) => e.id == updated.id,
                          );
                          if (idx == -1) return;
                          setState(() => items[idx] = updated);
                          await _saveMenuItemsToDb();
                        },
                      ),
                    ),
                  );
                },
                onSaveSettings: _saveVendorSettings,
                onUploadStallPhoto: _pickAndUploadStallPhoto,
                onOpenPromotions: () => setState(() => index = 3),
                onLogout: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const WelcomePage()),
                    (route) => false,
                  );
                },
                avatarBuilder: (b64, r) => _stallAvatarFromB64(b64, radius: r),
                prettyQueue: _prettyQueue,
              ),

              VendorMenuTab(
                items: items,
                isHalal: isHalal,
                stallTag: _stallTag,
                queueStatus: _queueStatus,
                onTapMenuItem: (item) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VendorMenuItemDetailPage(
                        item: item,
                        onItemSaved: (updated) async {
                          final idx = items.indexWhere(
                            (e) => e.id == updated.id,
                          );
                          if (idx == -1) return;
                          setState(() => items[idx] = updated);
                          await _saveMenuItemsToDb();
                        },
                      ),
                    ),
                  );
                },
                onSaveSettings: _saveVendorSettings,
                onSnack: _snack,
                onUploadPaynow: _pickAndUploadQr,
                paynowQrUrl: paynowQrUrl,
                onManageMenuItems: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManageVendorMenuPage(
                        items: items,
                        onItemsChanged: (newItems) async {
                          setState(() => items = newItems);
                          await _saveMenuItemsToDb();
                        },
                      ),
                    ),
                  );
                },
                prettyQueue: _prettyQueue,
              ),

              VendorOrdersTab(
                ordersStream: _ordersStream(u.uid),
                onToggleReady: (orderDocId, isReady) => _setOrderReady(
                  vendorUid: u.uid,
                  orderDocId: orderDocId,
                  isReady: isReady,
                ),
                onEnsureDisplayNo: (orderDocId, data) => _ensureOrderDisplayNo(
                  vendorUid: u.uid,
                  orderDocId: orderDocId,
                  data: data,
                ),
                queueStatus: _queueStatus,
                onQueueChange: (v) =>
                    _saveVendorSettings(stallTag: _stallTag, queueStatus: v),
              ),

              VendorPromotionsTab(
                vendorUid: u.uid,
                fcId: fcId,
                promptCtrl: _promoPromptCtrl,
                generating: _promoGenerating,
                previewB64: _promoPreviewB64,
                onGenerate: (prompt) => _generatePromoPreview(
                  prompt: prompt,
                  vendorUid: u.uid,
                  fcId: fcId ?? "",
                ),
                onAddPreview: () =>
                    _addPreviewPromoToDb(vendorUid: u.uid, fcId: fcId ?? ""),
                onCancel: () {
                  setState(() {
                    _promoPromptCtrl.clear();
                    _promoPreviewB64 = null;
                    _promoGenerating = false;
                  });
                },
                onUpload: () => _uploadPromoFromGallery(fcId: fcId ?? ""),
              ),

              VendorReviewsTab(
                vendorUid: u.uid,
                stallName: stallName,
                fcId: fcId,
              ),
            ];

            return Scaffold(
              body: SafeArea(bottom: false, child: pages[index]),
              bottomNavigationBar: SafeArea(
                top: false,
                child: NavigationBar(
                  selectedIndex: index,
                  indicatorColor: kPink.withOpacity(0.12),
                  onDestinationSelected: (i) => setState(() => index = i),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: "Home",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.restaurant_menu_outlined),
                      selectedIcon: Icon(Icons.restaurant_menu),
                      label: "Menu",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: "Orders",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.local_offer_outlined),
                      selectedIcon: Icon(Icons.local_offer),
                      label: "Promos",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.reviews_outlined),
                      selectedIcon: Icon(Icons.reviews),
                      label: "Reviews",
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Widget menuImage(
  String path, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  final p = path.trim();
  if (p.isEmpty) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF3F3F3),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: Colors.black38),
    );
  }

  if (p.startsWith("http")) {
    return Image.network(
      p,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: const Color(0xFFF3F3F3),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: Colors.black38),
      ),
    );
  }

  if (p.startsWith("b64:")) {
    try {
      final bytes = base64Decode(p.substring(4));
      return Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: const Color(0xFFF3F3F3),
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined, color: Colors.black38),
        ),
      );
    } catch (_) {
      return Container(
        width: width,
        height: height,
        color: const Color(0xFFF3F3F3),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: Colors.black38),
      );
    }
  }

  return Image.asset(
    p,
    fit: fit,
    width: width,
    height: height,
    errorBuilder: (_, __, ___) => Container(
      width: width,
      height: height,
      color: const Color(0xFFF3F3F3),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: Colors.black38),
    ),
  );
}

class VendorHomeTab extends StatelessWidget {
  const VendorHomeTab({
    super.key,
    required this.items,
    required this.vendorEmail,
    required this.stallName,
    required this.stallNo,
    required this.stallLocation,
    required this.foodcourtNo,
    required this.isHalal,
    required this.stallTag,
    required this.queueStatus,
    required this.stallPhotoB64,
    required this.onTapMenuItem,
    required this.onSaveSettings,
    required this.onUploadStallPhoto,
    required this.onOpenPromotions,
    required this.onLogout,
    required this.avatarBuilder,
    required this.prettyQueue,
  });

  static const Color kPink = Color(0xFFFF3D8D);

  final List<VendorMenuItem> items;

  final String vendorEmail;
  final String stallName;
  final String stallNo;
  final String stallLocation;
  final int? foodcourtNo;
  final bool isHalal;

  final String? stallTag;
  final String queueStatus;

  final String? stallPhotoB64;

  final void Function(VendorMenuItem item) onTapMenuItem;
  final Future<void> Function({
    required String? stallTag,
    required String queueStatus,
  })
  onSaveSettings;
  final Future<void> Function() onUploadStallPhoto;
  final VoidCallback onOpenPromotions;
  final Future<void> Function() onLogout;

  final Widget Function(String? b64, double radius) avatarBuilder;
  final String Function(String s) prettyQueue;

  void _openProfileSheet(BuildContext context) {
    final tagLabel = (stallTag == null || stallTag!.trim().isEmpty)
        ? "None"
        : stallTag!.trim();
    final fcLabel = (foodcourtNo == null)
        ? "Not set"
        : "Foodcourt $foodcourtNo";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        final mq = MediaQuery.of(context);
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: mq.size.height * 0.9),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                8,
                18,
                18 + mq.viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      avatarBuilder(stallPhotoB64, 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stallName,
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              vendorEmail,
                              style: GoogleFonts.manrope(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ProfileRow(label: "Foodcourt", value: fcLabel),
                  const SizedBox(height: 8),
                  _ProfileRow(label: "Stall", value: stallName),
                  const SizedBox(height: 8),
                  _ProfileRow(label: "Stall No", value: stallNo),
                  const SizedBox(height: 8),
                  _ProfileRow(label: "Location", value: stallLocation),
                  const SizedBox(height: 8),
                  _ProfileRow(label: "Halal", value: isHalal ? "Yes" : "No"),
                  const SizedBox(height: 8),
                  _ProfileRow(label: "Tag", value: tagLabel),
                  const SizedBox(height: 8),
                  _ProfileRow(label: "Queue", value: prettyQueue(queueStatus)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await onLogout();
                      },
                      icon: const Icon(Icons.logout),
                      label: Text(
                        "Logout",
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: const BorderSide(color: Color(0xFFEAEAEA)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          title,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
        ),
        content: Text(
          message,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Got it",
              style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tagLabel = (stallTag == null || stallTag!.trim().isEmpty)
        ? "No tag"
        : stallTag!;
    final queueLabel = prettyQueue(queueStatus);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Hi $stallName,",
                    style: GoogleFonts.manrope(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openProfileSheet(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.person_outline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Here’s an overview of your stall today.",
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  "Queue status",
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _showInfoDialog(
                    context,
                    title: "Queue Status Help",
                    message:
                        "Customers see this status before ordering. Keep it updated so waiting time expectations are clear.",
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _QueueSelector(
              value: queueStatus,
              onChanged: (v) =>
                  onSaveSettings(stallTag: stallTag, queueStatus: v),
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFEAEAEA)),
              ),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onUploadStallPhoto,
                    child: Stack(
                      children: [
                        avatarBuilder(stallPhotoB64, 26),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: kPink,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.3,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stallName,
                          style: GoogleFonts.manrope(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Stall $stallNo • $stallLocation",
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (isHalal)
                              _Pill(
                                text: "Halal",
                                bg: kPink.withOpacity(0.10),
                                fg: kPink,
                              ),
                            _Pill(text: tagLabel),
                            _Pill(text: queueLabel),
                            if (foodcourtNo != null)
                              _Pill(text: "FC$foodcourtNo"),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Text(
                  "Your menu items",
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _showInfoDialog(
                    context,
                    title: "Menu Cards",
                    message:
                        "Tap any card to edit details and customisations. Sold out items stay visible to customers.",
                  ),
                  child: const Icon(
                    Icons.help_outline,
                    size: 18,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onTapMenuItem(item),
                    child: Container(
                      width: 170,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEAEAEA)),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(18),
                                ),
                                child: SizedBox(
                                  height: 110,
                                  width: double.infinity,
                                  child: menuImage(
                                    item.imageUrl,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  12,
                                  0,
                                ),
                                child: Text(
                                  item.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  4,
                                  12,
                                  8,
                                ),
                                child: Text(
                                  "S\$${item.price.toStringAsFixed(2)}",
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: kPink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (item.soldOut)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "Sold out",
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Tip: Sold out items still show, but customers will see 'Sold out'.",
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black45,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: "Tip details",
                  onPressed: () => _showInfoDialog(
                    context,
                    title: "Tip",
                    message:
                        "Keep items visible and toggle sold out after restocking. This helps customers plan what to buy.",
                  ),
                  icon: const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEAEAEA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_outlined, color: kPink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Want more orders? Create your promotion today.",
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenPromotions,
                    child: Text(
                      "Open",
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w900,
                        color: kPink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.bg, this.fg});
  final String text;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg ?? Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFEAEAEA)),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: fg ?? Colors.black87,
        ),
      ),
    );
  }
}

class _QueueSelector extends StatelessWidget {
  const _QueueSelector({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const List<String> _order = ["VERY_BUSY", "MODERATE", "NO_QUEUE"];

  String _label(String s) {
    switch (s) {
      case "VERY_BUSY":
        return "Very busy";
      case "MODERATE":
        return "Moderate";
      case "NO_QUEUE":
        return "No queue";
      default:
        return s;
    }
  }

  Color _color(String s) {
    switch (s) {
      case "VERY_BUSY":
        return const Color(0xFFE53935);
      case "MODERATE":
        return const Color(0xFFFBC02D);
      case "NO_QUEUE":
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  String _assetFor(String s) {
    switch (s) {
      case "VERY_BUSY":
        return "assets/img/red.png";
      case "MODERATE":
        return "assets/img/yellow.png";
      case "NO_QUEUE":
        return "assets/img/green.png";
      default:
        return "assets/img/green.png";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _order.map((s) {
        final selected = s == value;
        final c = _color(s);
        return SizedBox(
          height: 40,
          child: OutlinedButton(
            onPressed: () => onChanged(s),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: selected ? c : const Color(0xFFEAEAEA),
                width: 1.4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              backgroundColor: selected
                  ? c.withOpacity(0.15)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(_assetFor(s), width: 14, height: 14),
                const SizedBox(width: 6),
                Text(
                  _label(s),
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    color: selected ? c : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class VendorMenuTab extends StatefulWidget {
  const VendorMenuTab({
    super.key,
    required this.items,
    required this.isHalal,
    required this.stallTag,
    required this.queueStatus,
    required this.onTapMenuItem,
    required this.onSaveSettings,
    required this.onSnack,
    required this.onUploadPaynow,
    required this.paynowQrUrl,
    required this.onManageMenuItems,
    required this.prettyQueue,
  });

  static const Color kPink = Color(0xFFFF3D8D);

  final List<VendorMenuItem> items;
  final bool isHalal;
  final String? stallTag;
  final String queueStatus;

  final void Function(VendorMenuItem item) onTapMenuItem;
  final Future<void> Function({
    required String? stallTag,
    required String queueStatus,
  })
  onSaveSettings;
  final void Function(String msg) onSnack;

  final VoidCallback onUploadPaynow;
  final String? paynowQrUrl;

  final VoidCallback onManageMenuItems;
  final String Function(String s) prettyQueue;

  @override
  State<VendorMenuTab> createState() => _VendorMenuTabState();
}

class _VendorMenuTabState extends State<VendorMenuTab> {
  static const String _allBadges = "All tags";
  final TextEditingController _searchCtrl = TextEditingController();
  String _badgeFilter = _allBadges;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tagLabel =
        (widget.stallTag == null || widget.stallTag!.trim().isEmpty)
        ? "No tag"
        : widget.stallTag!;
    final queueLabel = widget.prettyQueue(widget.queueStatus);
    final badges =
        widget.items
            .map((e) => e.badge.trim())
            .where((b) => b.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final badgeOptions = [_allBadges, ...badges];
    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredItems = widget.items.where((item) {
      final matchesQuery =
          query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.subtitle.toLowerCase().contains(query);
      final matchesBadge =
          _badgeFilter == _allBadges || item.badge.trim() == _badgeFilter;
      return matchesQuery && matchesBadge;
    }).toList();

    void showMenuHelpDialog() {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            "Menu Page Help",
            style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
          ),
          content: Text(
            "1) Upload/update PayNow QR.\n2) Add or remove menu items.\n3) Tap any item to edit details and customisations.\n4) Use search and tags to find items quickly.",
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "Got it",
                style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18 + 90),
        children: [
          Row(
            children: [
              Text(
                "Your menu",
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: showMenuHelpDialog,
                child: const Icon(
                  Icons.help_outline,
                  size: 19,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Upload QR + manage menu + sold out status.",
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFEAEAEA)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isHalal
                        ? "Halal • $tagLabel • $queueLabel"
                        : "$tagLabel • $queueLabel",
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    String? localTag = widget.stallTag;

                    await showModalBottomSheet(
                      context: context,
                      showDragHandle: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                      ),
                      builder: (_) {
                        return StatefulBuilder(
                          builder: (context, setModal) {
                            return SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  8,
                                  18,
                                  18,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Stall settings",
                                      style: GoogleFonts.manrope(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    DropdownButtonFormField<String?>(
                                      key: ValueKey(localTag),
                                      initialValue:
                                          (localTag == null ||
                                              localTag!.trim().isEmpty)
                                          ? null
                                          : localTag!.trim(),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text("No tag"),
                                        ),
                                        ..._VendorHomePageState.allowedTags.map(
                                          (t) => DropdownMenuItem<String?>(
                                            value: t,
                                            child: Text(t),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setModal(() => localTag = v),
                                      decoration: InputDecoration(
                                        labelText: "Stall tag",
                                        labelStyle: GoogleFonts.manrope(
                                          fontWeight: FontWeight.w800,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: ElevatedButton(
                                        onPressed: () async {
                                          if (localTag != null &&
                                              localTag!.trim().isNotEmpty &&
                                              !_VendorHomePageState.allowedTags
                                                  .contains(localTag)) {
                                            widget.onSnack("Invalid tag");
                                            return;
                                          }
                                          await widget.onSaveSettings(
                                            stallTag: localTag,
                                            queueStatus: widget.queueStatus,
                                          );
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: VendorMenuTab.kPink,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          "Save",
                                          style: GoogleFonts.manrope(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: VendorMenuTab.kPink.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.tune, color: VendorMenuTab.kPink),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          _QrRoleCard(
            title: "PayNow QR",
            subtitle:
                (widget.paynowQrUrl == null ||
                    widget.paynowQrUrl!.trim().isEmpty)
                ? "Default PayLah image"
                : "QR uploaded",
            assetPath: "assets/img/paylah.png",
            imageUrl: widget.paynowQrUrl,
          ),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: widget.onUploadPaynow,
              style: ElevatedButton.styleFrom(
                backgroundColor: VendorMenuTab.kPink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                "Upload / update your QR code",
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: widget.onManageMenuItems,
              style: ElevatedButton.styleFrom(
                backgroundColor: VendorMenuTab.kPink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                "Add / remove menu items",
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Text(
                "Your menu items",
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(
                        "Editing Items",
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                      ),
                      content: Text(
                        "Tap any item card to edit image, price, description, sold out status, and customisations.",
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            "Got it",
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    hintText: "Search menu items",
                    hintStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: Colors.black38,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFEAEAEA)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFEAEAEA)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFFF3D8D)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<String>(
                  initialValue: badgeOptions.contains(_badgeFilter)
                      ? _badgeFilter
                      : _allBadges,
                  items: badgeOptions
                      .map(
                        (b) =>
                            DropdownMenuItem<String>(value: b, child: Text(b)),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _badgeFilter = v ?? _allBadges),
                  decoration: InputDecoration(
                    labelText: "Tags",
                    labelStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFEAEAEA)),
                    ),
                  ),
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                  icon: const Icon(Icons.expand_more),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (filteredItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFEAEAEA)),
              ),
              child: Text(
                "No items match your search.",
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredItems.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (context, i) {
                final item = filteredItems[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => widget.onTapMenuItem(item),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEAEAEA)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(18),
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: menuImage(
                                    item.imageUrl,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                if (item.badge.trim().isNotEmpty)
                                  Positioned(
                                    left: 8,
                                    top: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade600,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        item.badge,
                                        style: GoogleFonts.manrope(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (item.soldOut)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.white.withOpacity(0.75),
                                      alignment: Alignment.center,
                                      child: Text(
                                        "Sold out",
                                        style: GoogleFonts.manrope(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (item.subtitle.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                            child: Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                          child: Text(
                            "S\$${item.price.toStringAsFixed(2)}",
                            style: GoogleFonts.manrope(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: VendorMenuTab.kPink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _QrRoleCard extends StatelessWidget {
  const _QrRoleCard({
    required this.title,
    required this.subtitle,
    required this.assetPath,
    this.imageUrl,
  });

  final String title;
  final String subtitle;
  final String assetPath;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final hasCustom = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEAEA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3D8D).withOpacity(0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasCustom
                    ? menuImage(
                        imageUrl!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                      )
                    : Image.asset(
                        assetPath,
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3D8D).withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              "QR",
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFFF3D8D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VendorOrdersTab extends StatelessWidget {
  const VendorOrdersTab({
    super.key,
    required this.ordersStream,
    required this.onToggleReady,
    required this.onEnsureDisplayNo,
    required this.queueStatus,
    required this.onQueueChange,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>> ordersStream;
  final void Function(String orderDocId, bool isReady) onToggleReady;
  final Future<void> Function(String orderDocId, Map<String, dynamic> data)
  onEnsureDisplayNo;
  final String queueStatus;
  final ValueChanged<String> onQueueChange;

  String _status(Map<String, dynamic> d) =>
      ((d['status'] as String?) ?? 'PLACED').trim().toUpperCase().replaceAll(
        ' ',
        '_',
      );

  bool _isReady(Map<String, dynamic> d) => _status(d) == 'READY';
  bool _isPickedUp(Map<String, dynamic> d) =>
      _status(d) == 'PICKED_UP' || _status(d) == 'PICKEDUP';

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          title,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
        ),
        content: Text(
          message,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Got it",
              style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ordersStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18 + 90),
              children: [
                Row(
                  children: [
                    Text(
                      "Queue status",
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _showInfoDialog(
                        context,
                        title: "Queue Status",
                        message:
                            "Set your current queue so customers can judge waiting time before they order.",
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _QueueSelector(value: queueStatus, onChanged: onQueueChange),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      "Orders",
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _showInfoDialog(
                        context,
                        title: "Orders Help",
                        message:
                            "Each order appears here. Tick 'Mark ready for pickup' when food is ready so customers can collect.",
                      ),
                      child: const Icon(
                        Icons.help_outline,
                        size: 18,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEAEAEA)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 40,
                        color: Colors.black45,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Orders failed to load",
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${snap.error}",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final docs = snap.data?.docs ?? [];
          docs.sort((a, b) {
            final at =
                (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                0;
            final bt =
                (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18 + 90),
            children: [
              Row(
                children: [
                  Text(
                    "Queue status",
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _showInfoDialog(
                      context,
                      title: "Queue Status",
                      message:
                          "Set your current queue so customers can judge waiting time before they order.",
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _QueueSelector(value: queueStatus, onChanged: onQueueChange),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    "Orders",
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _showInfoDialog(
                      context,
                      title: "Orders Help",
                      message:
                          "Each order appears here. Tick 'Mark ready for pickup' when food is ready so customers can collect.",
                    ),
                    child: const Icon(
                      Icons.help_outline,
                      size: 18,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEAEAEA)),
                ),
                child: Text(
                  "Quick tip: New orders appear automatically. Keep this page open during peak times.",
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              if (snap.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (docs.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEAEAEA)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: 40,
                        color: Colors.black45,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "No orders yet",
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "When customers order, you’ll see it here.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...docs.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final doc = entry.value;
                  final d = doc.data();
                  final displayNo = (d['displayNo'] as num?)?.toInt() ?? 0;
                  if (displayNo <= 0) {
                    onEnsureDisplayNo(doc.id, d);
                  }
                  final effectiveDisplayNo = displayNo > 0
                      ? displayNo
                      : (docs.length - idx);
                  final itemCount = (d['itemCount'] as num?)?.toInt() ?? 0;
                  final isReady = _isReady(d);
                  final isPickedUp = _isPickedUp(d);
                  final isActive = !isPickedUp;
                  const activeAccent = Color(0xFFFF3D8D);
                  final activeBg = activeAccent.withOpacity(0.08);
                  final activeBorder = activeAccent.withOpacity(0.45);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isActive ? activeBg : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive
                              ? activeBorder
                              : const Color(0xFFEAEAEA),
                        ),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: Text(
                              "Order #$effectiveDisplayNo",
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w900,
                                color: isActive ? activeAccent : Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              isPickedUp
                                  ? "$itemCount items • Picked up"
                                  : (isReady
                                        ? "$itemCount items • Ready"
                                        : "$itemCount items • Placed"),
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w600,
                                color: isActive ? activeAccent : Colors.black54,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: isActive ? activeAccent : Colors.black54,
                            ),
                          ),
                          if (!isPickedUp)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isReady,
                                    onChanged: (v) =>
                                        onToggleReady(doc.id, v ?? false),
                                  ),
                                  Text(
                                    "Mark ready for pickup",
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w700,
                                      color: activeAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class VendorPromotionsTab extends StatelessWidget {
  const VendorPromotionsTab({
    super.key,
    required this.vendorUid,
    required this.fcId,
    required this.promptCtrl,
    required this.generating,
    required this.previewB64,
    required this.onGenerate,
    required this.onAddPreview,
    required this.onCancel,
    required this.onUpload,
  });

  final String vendorUid;
  final String? fcId;
  final TextEditingController promptCtrl;
  final bool generating;
  final String? previewB64;
  final Future<void> Function(String prompt) onGenerate;
  final Future<void> Function() onAddPreview;
  final VoidCallback onCancel;
  final VoidCallback onUpload;

  static const Color kPink = Color(0xFFFF3D8D);

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          title,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
        ),
        content: Text(
          message,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Got it",
              style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFc = fcId != null && fcId!.trim().isNotEmpty;
    final preview = (previewB64 ?? "").trim();
    Uint8List? decodeB64(String s) {
      try {
        return base64Decode(s);
      } catch (_) {
        return null;
      }
    }

    Widget promoImage(String? imageUrl, String? imageB64) {
      final url = (imageUrl ?? "").trim();
      if (url.isNotEmpty) {
        return Image.network(url, fit: BoxFit.cover);
      }
      final b64 = (imageB64 ?? "").trim();
      final bytes = b64.isEmpty ? null : decodeB64(b64);
      if (bytes == null) {
        return Container(
          height: 180,
          color: Colors.black.withOpacity(0.06),
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined, color: Colors.black45),
        );
      }
      return Image.memory(bytes, fit: BoxFit.cover);
    }

    Future<void> deletePromo({
      required String promoId,
      required String? imageB64,
    }) async {
      if (fcId == null || fcId!.trim().isEmpty) return;

      final promosCol = FirebaseFirestore.instance
          .collection('foodcourts')
          .doc(fcId)
          .collection('stalls')
          .doc(vendorUid)
          .collection('promos');

      try {
        if (promoId.trim().isNotEmpty) {
          await promosCol.doc(promoId).delete();
          return;
        }
      } catch (_) {
        final b64 = (imageB64 ?? "").trim();
        if (b64.isEmpty) return;
        final q = await promosCol
            .where('imageB64', isEqualTo: b64)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) await q.docs.first.reference.delete();
      }
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18 + 90),
        children: [
          Row(
            children: [
              Text(
                "Promotions",
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _showInfoDialog(
                  context,
                  title: "Promotions Help",
                  message:
                      "Generate or upload posters, then press 'Add this poster to your promos' to publish them.",
                ),
                child: const Icon(
                  Icons.help_outline,
                  size: 19,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Highlight your deals to attract more students/staff.",
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEAEAEA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "AI Poster Generator",
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _showInfoDialog(
                        context,
                        title: "Generator Guide",
                        message:
                            "1) Enter promo idea.\n2) Generate or upload.\n3) Preview image.\n4) Tap Add to publish in your promos list.",
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Describe your promo (e.g. \"Buy 1 get 1 milk tea, bright summer theme\").",
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: promptCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "Type your poster prompt...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (!hasFc || generating)
                        ? null
                        : () => onGenerate(promptCtrl.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: generating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            "Generate poster",
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: (!hasFc || generating) ? null : onUpload,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(
                      "Upload poster from device",
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: (!hasFc || generating) ? null : onAddPreview,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        "Add this poster to your promos",
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kPink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      "Cancel",
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                if (!hasFc)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      "Set a valid foodcourt in your profile to enable promos.",
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: (decodeB64(preview) == null)
                        ? Container(
                            height: 180,
                            color: Colors.black.withOpacity(0.06),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.black45,
                            ),
                          )
                        : Image.memory(decodeB64(preview)!, fit: BoxFit.cover),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Text(
                "Your promos",
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _showInfoDialog(
                  context,
                  title: "Your Promos",
                  message:
                      "These are live posters customers can see. Remove outdated promos anytime using the delete button.",
                ),
                child: const Icon(
                  Icons.info_outline,
                  size: 17,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (!hasFc)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFEAEAEA)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.photo_outlined,
                    size: 40,
                    color: Colors.black45,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "No promotions yet",
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Add a poster after setting your foodcourt number.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('foodcourts')
                  .doc(fcId)
                  .collection('stalls')
                  .doc(vendorUid)
                  .collection('promos')
                  .orderBy('createdAt', descending: true)
                  .limit(30)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text(
                    "Failed to load promos: ${snap.error}",
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: Colors.redAccent,
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEAEAEA)),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.photo_outlined,
                          size: 40,
                          color: Colors.black45,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "No promotions yet",
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Generate a poster to show your latest deals.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: docs.map((d) {
                    final imageUrl = (d.data()['imageUrl'] as String?)?.trim();
                    final imageB64 = (d.data()['imageB64'] as String?)?.trim();
                    final promoId = d.id;
                    if ((imageUrl == null || imageUrl.isEmpty) &&
                        (imageB64 == null || imageB64.isEmpty)) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFEAEAEA),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: promoImage(imageUrl, imageB64),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: InkWell(
                              onTap: () async {
                                await deletePromo(
                                  promoId: promoId,
                                  imageB64: imageB64,
                                );
                              },
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.65),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}

class PromoUploadPage extends StatefulWidget {
  const PromoUploadPage({super.key});

  @override
  State<PromoUploadPage> createState() => _PromoUploadPageState();
}

class _PromoUploadPageState extends State<PromoUploadPage> {
  static const Color kPink = Color(0xFFFF3D8D);
  String? selectedPath;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;
    setState(() => selectedPath = picked.path);
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = selectedPath != null && selectedPath!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Upload promotion",
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18 + 90),
          children: [
            Text(
              "Add a poster",
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Choose a poster from your gallery.",
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 14),
            if (!hasImage)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEAEAEA)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.photo_outlined,
                      size: 40,
                      color: Colors.black45,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "No image selected",
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Tap upload to choose a poster.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEAEAEA)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.file(File(selectedPath!), fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  "Upload poster",
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: hasImage
                    ? () => Navigator.pop(context, selectedPath)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  "Add promotion",
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
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

class VendorReviewsTab extends StatelessWidget {
  const VendorReviewsTab({
    super.key,
    required this.vendorUid,
    required this.stallName,
    required this.fcId,
  });

  final String vendorUid;
  final String stallName;
  final String? fcId;

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          "Reviews Help",
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
        ),
        content: Text(
          "Customer ratings and comments appear here. Use this feedback to improve menu items and service speed.",
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Got it",
              style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  String _normalize(String raw) {
    final c = raw.trim().toLowerCase();
    return c
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Widget _emptyReviewsState(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18 + 90),
      children: [
        Row(
          children: [
            Text(
              "Reviews",
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _showInfoDialog(context),
              child: const Icon(
                Icons.info_outline,
                size: 18,
                color: Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "Monitor customer feedback and improve based on common comments.",
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEAEAEA)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(
                  Icons.rate_review_outlined,
                  size: 36,
                  color: Colors.black45,
                ),
                const SizedBox(height: 8),
                Text(
                  "No reviews yet",
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  "Customer reviews will appear here once submitted.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (fcId == null || fcId!.trim().isEmpty) {
      return _emptyReviewsState(context);
    }

    final normalizedStallName = _normalize(stallName);

    return SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('foodcourts')
            .doc(fcId)
            .collection('stalls')
            .doc(vendorUid)
            .collection('reviews')
            .orderBy('createdAt', descending: true)
            .limit(400)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _emptyReviewsState(context);
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snap.data?.docs ?? const [];
          final filtered = allDocs.where((d) {
            final data = d.data();
            if (data.containsKey('rating')) return true;
            final reviewStallName = _normalize(
              (data['stallName'] as String?) ?? "",
            );
            return normalizedStallName.isNotEmpty &&
                reviewStallName.isNotEmpty &&
                (reviewStallName == normalizedStallName ||
                    reviewStallName.contains(normalizedStallName) ||
                    normalizedStallName.contains(reviewStallName));
          }).toList();

          if (filtered.isEmpty) {
            return _emptyReviewsState(context);
          }

          final totalRating = filtered.fold<int>(
            0,
            (sum, d) => sum + ((d.data()['rating'] as num?)?.toInt() ?? 0),
          );
          final avgRating = totalRating / filtered.length;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18 + 90),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          "Reviews",
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => _showInfoDialog(context),
                          child: const Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Monitor customer feedback and improve based on common comments.",
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEAEAEA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.orange,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "${avgRating.toStringAsFixed(1)} average",
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "${filtered.length} reviews",
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              final data = filtered[i - 1].data();
              final userName =
                  (data['userName'] as String?)?.trim() ?? "Student";
              final comment = (data['comment'] as String?)?.trim() ?? "";
              final stars = (data['rating'] as num?)?.toInt() ?? 0;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEAEAEA)),
                ),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(
                    userName,
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    comment.isEmpty ? "No comment provided." : comment,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (idx) => Icon(
                        idx < stars ? Icons.star : Icons.star_border,
                        size: 18,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: filtered.length + 1,
          );
        },
      ),
    );
  }
}

class ManageVendorMenuPage extends StatefulWidget {
  const ManageVendorMenuPage({
    super.key,
    required this.items,
    required this.onItemsChanged,
  });

  final List<VendorMenuItem> items;
  final Future<void> Function(List<VendorMenuItem> newItems) onItemsChanged;

  @override
  State<ManageVendorMenuPage> createState() => _ManageVendorMenuPageState();
}

class _ManageVendorMenuPageState extends State<ManageVendorMenuPage> {
  static const Color kPink = Color(0xFFFF3D8D);
  late List<VendorMenuItem> items;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    items = List.of(widget.items);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<String?> _uploadMenuItemImage({
    required String vendorUid,
    required String itemId,
  }) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 900,
    );
    if (picked == null) return null;

    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > 850 * 1024) {
        _snack("Image too large. Choose a smaller image.");
        return null;
      }

      return "b64:${base64Encode(bytes)}";
    } catch (e) {
      _snack("Image upload failed: ${e.toString()}");
      return null;
    }
  }

  Future<void> _addOrEditItem({VendorMenuItem? existing, int? index}) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final nameCtrl = TextEditingController(text: existing?.name ?? "");
    final subtitleCtrl = TextEditingController(text: existing?.subtitle ?? "");
    final priceCtrl = TextEditingController(
      text: existing != null ? existing.price.toStringAsFixed(2) : "0.00",
    );
    final badgeCtrl = TextEditingController(text: existing?.badge ?? "");

    final draftId =
        existing?.id ?? "item_${DateTime.now().millisecondsSinceEpoch}";
    String? imageUrl = existing?.imageUrl;
    bool soldOut = existing?.soldOut ?? false;

    final isEditing = existing != null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return AlertDialog(
              title: Text(
                isEditing ? "Edit menu item" : "Add menu item",
                style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: "Item name"),
                    ),
                    TextField(
                      controller: subtitleCtrl,
                      decoration: const InputDecoration(
                        labelText: "Short description",
                      ),
                    ),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: "Base price (e.g. 5.90)",
                      ),
                    ),
                    TextField(
                      controller: badgeCtrl,
                      decoration: const InputDecoration(
                        labelText: "Badge (optional)",
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (imageUrl != null && imageUrl!.isNotEmpty)
                      Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEAEAEA)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: menuImage(imageUrl!, fit: BoxFit.cover),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final url = await _uploadMenuItemImage(
                            vendorUid: u.uid,
                            itemId: draftId,
                          );
                          if (url == null) return;
                          setModal(() => imageUrl = url);
                          _snack("Image uploaded");
                        },
                        icon: const Icon(Icons.upload_file_outlined),
                        label: Text(
                          "Upload image",
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        "Sold out",
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                      ),
                      value: soldOut,
                      onChanged: (v) => setModal(() => soldOut = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(isEditing ? "Save" : "Add"),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack("Please enter a name");
      return;
    }

    final subtitle = subtitleCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
    final badge = badgeCtrl.text.trim();
    final finalImageUrl = imageUrl ?? "";

    setState(() {
      if (isEditing && index != null) {
        items[index] = VendorMenuItem(
          id: existing.id,
          name: name,
          subtitle: subtitle,
          price: price,
          badge: badge,
          imageUrl: finalImageUrl,
          optionGroups: existing.optionGroups.map((g) => g.copy()).toList(),
          soldOut: soldOut,
        );
      } else {
        items.add(
          VendorMenuItem(
            id: draftId,
            name: name,
            subtitle: subtitle,
            price: price,
            badge: badge,
            imageUrl: finalImageUrl,
            optionGroups: const [],
            soldOut: soldOut,
          ),
        );
      }
    });

    await widget.onItemsChanged(items);
    _snack(isEditing ? "Menu item updated" : "Menu item added");
  }

  Future<void> _removeItem(int index) async {
    final item = items[index];

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(
            "Remove menu item",
            style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
          ),
          content: Text(
            "Remove \"${item.name}\" from your menu?",
            style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Remove"),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    setState(() => items.removeAt(index));
    await widget.onItemsChanged(items);
    _snack("Menu item removed");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Manage menu items",
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
        ),
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  "You don't have any items yet.\nTap the button below to add your first menu item.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18 + 110),
              itemBuilder: (context, index) {
                final item = items[index];
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEAEAEA)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: menuImage(
                        item.imageUrl,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(
                      item.name,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "S\$${item.price.toStringAsFixed(2)}${item.badge.isNotEmpty ? " • ${item.badge}" : ""}",
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: kPink,
                          ),
                        ),
                        if (item.soldOut) ...[
                          const SizedBox(height: 4),
                          Text(
                            "Sold out",
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: "Edit",
                          onPressed: () =>
                              _addOrEditItem(existing: item, index: index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: "Remove",
                          onPressed: () => _removeItem(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: items.length,
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditItem(),
        icon: const Icon(Icons.add),
        label: Text(
          "Add menu item",
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        backgroundColor: kPink,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class VendorMenuItemDetailPage extends StatefulWidget {
  const VendorMenuItemDetailPage({
    super.key,
    required this.item,
    required this.onItemSaved,
  });

  final VendorMenuItem item;
  final Future<void> Function(VendorMenuItem updatedItem) onItemSaved;

  @override
  State<VendorMenuItemDetailPage> createState() =>
      _VendorMenuItemDetailPageState();
}

class _VendorMenuItemDetailPageState extends State<VendorMenuItemDetailPage> {
  static const Color kPink = Color(0xFFFF3D8D);

  late List<OptionGroup> groups;

  @override
  void initState() {
    super.initState();
    groups = widget.item.optionGroups.map((g) => g.copy()).toList();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _addGroup() async {
    final titleCtrl = TextEditingController();
    final maxCtrl = TextEditingController(text: "1");

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          "Add customisation",
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: "Group name (e.g. Sides)",
              ),
            ),
            TextField(
              controller: maxCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Max selections"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Add"),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final max = int.tryParse(maxCtrl.text.trim()) ?? 1;
    if (title.isEmpty) {
      _snack("Please enter group name");
      return;
    }

    setState(() {
      groups.add(
        OptionGroup(title: title, maxSelect: max <= 0 ? 1 : max, choices: []),
      );
    });
  }

  Future<void> _addChoice(int groupIndex) async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: "0.00");

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          "Add option",
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Option name"),
            ),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: "Extra price"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Add"),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
    if (name.isEmpty) {
      _snack("Please enter option name");
      return;
    }

    setState(() {
      groups[groupIndex].choices.add(
        OptionChoice(label: name, extraPrice: price),
      );
    });
  }

  void _removeGroup(int groupIndex) {
    setState(() => groups.removeAt(groupIndex));
  }

  void _removeChoice(int groupIndex, int choiceIndex) {
    setState(() => groups[groupIndex].choices.removeAt(choiceIndex));
  }

  Future<void> _saveItem() async {
    final updated = VendorMenuItem(
      id: widget.item.id,
      name: widget.item.name,
      subtitle: widget.item.subtitle,
      price: widget.item.price,
      badge: widget.item.badge,
      imageUrl: widget.item.imageUrl,
      optionGroups: groups.map((g) => g.copy()).toList(),
      soldOut: widget.item.soldOut,
    );

    await widget.onItemSaved(updated);
    if (!mounted) return;
    _snack("Customisations saved");
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1.4,
                    child: menuImage(item.imageUrl, fit: BoxFit.cover),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.6),
                            Colors.black.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Positioned(
                    bottom: 18,
                    left: 18,
                    right: 18,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: GoogleFonts.manrope(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "S\$${item.price.toStringAsFixed(2)}",
                              style: GoogleFonts.manrope(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Base price",
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                child: Text(
                  item.subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Text(
                  "Vendor: add/edit customisations below (name, price, max selections).",
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, groupIndex) {
                final g = groups[groupIndex];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              g.title,
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            "Max ${g.maxSelect}",
                            style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.black45,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removeGroup(groupIndex),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                      if (g.choices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            "No options yet.",
                            style: GoogleFonts.manrope(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                      ...List.generate(g.choices.length, (choiceIndex) {
                        final c = g.choices[choiceIndex];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            c.label,
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            "+S\$${c.extraPrice.toStringAsFixed(2)}",
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                          trailing: IconButton(
                            onPressed: () =>
                                _removeChoice(groupIndex, choiceIndex),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: () => _addChoice(groupIndex),
                        icon: const Icon(Icons.add),
                        label: Text(
                          "Add option",
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                );
              }, childCount: groups.length),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: _addGroup,
                        icon: const Icon(Icons.add),
                        label: Text(
                          "Add customisation",
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _saveItem,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPink,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          "Save item",
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              color: Colors.black54,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class PromoPoster {
  const PromoPoster.asset(this.path) : isAsset = true;
  const PromoPoster.file(this.path) : isAsset = false;

  final String path;
  final bool isAsset;
}

class VendorMenuItem {
  VendorMenuItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.price,
    required this.badge,
    required this.imageUrl,
    required this.optionGroups,
    required this.soldOut,
  });

  final String id;
  final String name;
  final String subtitle;
  final double price;
  final String badge;
  final String imageUrl;
  final List<OptionGroup> optionGroups;
  final bool soldOut;
}

class OptionGroup {
  OptionGroup({
    required this.title,
    required this.maxSelect,
    required this.choices,
  });
  final String title;
  final int maxSelect;
  final List<OptionChoice> choices;

  OptionGroup copy() => OptionGroup(
    title: title,
    maxSelect: maxSelect,
    choices: choices
        .map((c) => OptionChoice(label: c.label, extraPrice: c.extraPrice))
        .toList(),
  );
}

class OptionChoice {
  OptionChoice({required this.label, required this.extraPrice});
  final String label;
  final double extraPrice;
}
