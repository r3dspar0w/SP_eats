import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'welcome_page.dart';

Widget buildAnyImage(
  String pathOrUrl, {
  double? w,
  double? h,
  BoxFit fit = BoxFit.cover,
}) {
  final s = pathOrUrl.trim();

  if (s.isEmpty) {
    return Container(
      width: w,
      height: h,
      color: Colors.black.withOpacity(0.06),
      child: const Icon(Icons.image_outlined, color: Colors.black45),
    );
  }

  if (s.startsWith("b64:")) {
    try {
      final b64 = s.substring(4);
      final bytes = base64Decode(b64);
      return Image.memory(bytes, width: w, height: h, fit: fit);
    } catch (_) {
      return Container(
        width: w,
        height: h,
        color: Colors.black.withOpacity(0.06),
        child: const Icon(Icons.broken_image_outlined, color: Colors.black45),
      );
    }
  }

  if (s.startsWith("http://") || s.startsWith("https://")) {
    return Image.network(
      s,
      width: w,
      height: h,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        width: w,
        height: h,
        color: Colors.black.withOpacity(0.06),
        child: const Icon(Icons.broken_image_outlined, color: Colors.black45),
      ),
    );
  }

  return Image.asset(
    s,
    width: w,
    height: h,
    fit: fit,
    errorBuilder: (_, __, ___) => Container(
      width: w,
      height: h,
      color: Colors.black.withOpacity(0.06),
      child: const Icon(Icons.broken_image_outlined, color: Colors.black45),
    ),
  );
}

class ConsumerHomePage extends StatefulWidget {
  const ConsumerHomePage({super.key});

  @override
  State<ConsumerHomePage> createState() => _ConsumerHomePageState();
}

class _ConsumerHomePageState extends State<ConsumerHomePage> {
  static const Color kPink = Color(0xFFFF3D8D);
  static const Color kBgSoft = Color(0xFFFFF1F6);
  static const List<String> _knownFoodCourtIds = [
    'fc1',
    'fc2',
    'fc3',
    'fc4',
    'fc5',
    'fc6',
    'moberly_cafe',
    'old_chang_kee',
  ];

  int index = 0;

  late final List<PlaceModel> places;
  late final List<PromoModel> promos;

  late final List<ConsumerOrder> orders;
  late final List<ConsumerReview> reviews;

  String? selectedPlaceId;
  final Map<String, bool> tagFilters = {
    "Halal": false,
    "Vegetarian": false,
    "Western": false,
    "Indian": false,
    "Thai": false,
    "Chinese": false,
    "Korean": false,
    "Japanese": false,
    "Drinks": false,
    "Dessert": false,
  };

  final TextEditingController searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    places = _buildPlaces();
    promos = _buildPromos();
    orders = _buildOrders();
    reviews = _buildReviews();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  List<PlaceModel> _buildPlaces() {
    return const [
      PlaceModel(
        id: "all",
        name: "All places",
        subtitle: "Explore everything",
        imagePath: "assets/img/fc1.png",
      ),
      PlaceModel(
        id: "fc1",
        name: "Food Court 1",
        subtitle: "Rice - Halal - Local",
        imagePath: "assets/img/fc1.png",
      ),
      PlaceModel(
        id: "fc2",
        name: "Food Court 2",
        subtitle: "Noodles - Bento - Indian",
        imagePath: "assets/img/fc2.png",
      ),
      PlaceModel(
        id: "fc3",
        name: "Food Court 3",
        subtitle: "Quick bites - Snacks",
        imagePath: "assets/img/fc3.png",
      ),
      PlaceModel(
        id: "fc4",
        name: "Food Court 4",
        subtitle: "Mix - Drinks",
        imagePath: "assets/img/fc4.png",
      ),
      PlaceModel(
        id: "fc5",
        name: "Food Court 5",
        subtitle: "Western - Local",
        imagePath: "assets/img/fc5.png",
      ),
      PlaceModel(
        id: "fc6",
        name: "Food Court 6",
        subtitle: "Dessert - Drinks",
        imagePath: "assets/img/fc6.png",
      ),
      PlaceModel(
        id: "moberly_cafe",
        name: "Moberly Cafe",
        subtitle: "Brunch - Pasta",
        imagePath: "assets/img/moberly.png",
      ),
      PlaceModel(
        id: "old_chang_kee",
        name: "Old Chang Kee",
        subtitle: "Snacks - Fast",
        imagePath: "assets/img/old_chang_kee.png",
      ),
    ];
  }

  List<PromoModel> _buildPromos() {
    return const [
      PromoModel(
        title: "Promotions - Deals ",
        imagePath: "assets/img/fc1.png",
        stallName: "Stall",
      ),
      PromoModel(
        title: "Promotions - Deals ",
        imagePath: "assets/img/fc2.png",
        stallName: "Stall",
      ),
      PromoModel(
        title: "Promotions - Deals ",
        imagePath: "assets/img/fc1.png",
        stallName: "Stall",
      ),
    ];
  }

  List<ConsumerOrder> _buildOrders() => [];
  List<ConsumerReview> _buildReviews() => [];

  Stream<List<StallModel>> _vendorStallsStream() async* {
    yield await _fetchVendorStallsFromKnownFoodcourts();
    yield* Stream.periodic(
      const Duration(seconds: 4),
    ).asyncMap((_) => _fetchVendorStallsFromKnownFoodcourts());
  }

  Future<void> _mergeVendorProfiles(
    Map<String, Map<String, dynamic>> rawByUid,
  ) async {
    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'vendor')
          .get();

      if (rawByUid.isEmpty) {
        for (final doc in userSnap.docs) {
          rawByUid[doc.id] = Map<String, dynamic>.from(doc.data());
        }
      } else {
        for (final doc in userSnap.docs) {
          final uid = doc.id;
          if (!rawByUid.containsKey(uid)) continue;
          final existing = rawByUid[uid]!;
          final userData = doc.data();
          for (final e in userData.entries) {
            final key = e.key;
            final val = e.value;
            if (!existing.containsKey(key) ||
                existing[key] == null ||
                (existing[key] is String &&
                    (existing[key] as String).trim().isEmpty)) {
              existing[key] = val;
            }
          }
          rawByUid[uid] = existing;
        }
      }
    } catch (_) {}
  }

  Future<List<StallModel>> _fetchVendorStallsFromKnownFoodcourts() async {
    final rawByUid = <String, Map<String, dynamic>>{};

    for (final fcId in _knownFoodCourtIds) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('foodcourts')
            .doc(fcId)
            .collection('stalls')
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final vendorUid = _vendorUidFromStallDoc(data, doc.id);
          final merged = _normalizedStallData(
            data,
            vendorUid,
            fallbackFoodCourtId: fcId,
          );
          merged['stallDocId'] = doc.id;
          rawByUid[vendorUid] = merged;
        }
      } catch (_) {
        // Skip inaccessible foodcourts and keep loading others.
      }
    }

    await _mergeVendorProfiles(rawByUid);
    return _toSortedVisibleStalls(rawByUid);
  }

  String _vendorUidFromStallDoc(Map<String, dynamic> data, String docId) {
    if ((data['vendorUid'] as String?)?.trim().isNotEmpty == true) {
      return (data['vendorUid'] as String).trim();
    }
    if ((data['uid'] as String?)?.trim().isNotEmpty == true) {
      return (data['uid'] as String).trim();
    }
    return docId;
  }

  Map<String, dynamic> _normalizedStallData(
    Map<String, dynamic> data,
    String vendorUid, {
    String? fallbackFoodCourtId,
  }) {
    final merged = Map<String, dynamic>.from(data);
    merged.putIfAbsent('uid', () => vendorUid);
    if ((merged['foodCourtId'] as String?)?.trim().isEmpty ?? true) {
      if (fallbackFoodCourtId != null && fallbackFoodCourtId.isNotEmpty) {
        merged['foodCourtId'] = fallbackFoodCourtId;
      }
    }
    return merged;
  }

  List<StallModel> _toSortedVisibleStalls(
    Map<String, Map<String, dynamic>> rawByUid,
  ) {
    final out = rawByUid.entries
        .map((e) => _stallFromData(e.key, e.value))
        .toList();

    out.sort((a, b) {
      final byPlace = _placeSortIndex(
        a.placeId,
      ).compareTo(_placeSortIndex(b.placeId));
      if (byPlace != 0) return byPlace;
      final byStallNo = _parseStallNo(
        a.stallNo,
      ).compareTo(_parseStallNo(b.stallNo));
      if (byStallNo != 0) return byStallNo;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  int _placeSortIndex(String placeId) {
    switch (placeId.toLowerCase()) {
      case 'fc1':
        return 1;
      case 'fc2':
        return 2;
      case 'fc3':
        return 3;
      case 'fc4':
        return 4;
      case 'fc5':
        return 5;
      case 'fc6':
        return 6;
      case 'moberly_cafe':
      case 'cafe1':
      case 'cafe2':
      case 'moberly':
        return 7;
      case 'old_chang_kee':
      case 'ock':
        return 8;
      default:
        return 999;
    }
  }

  int _parseStallNo(String? stallNo) {
    if (stallNo == null) return 9999;
    final digits = stallNo.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 9999;
    return int.tryParse(digits) ?? 9999;
  }

  Stream<List<PromoModel>> _promosStream() async* {
    yield await _fetchPromosFromKnownFoodcourts();
    yield* Stream.periodic(
      const Duration(seconds: 6),
    ).asyncMap((_) => _fetchPromosFromKnownFoodcourts());
  }

  List<PromoModel> _promosFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String stallName,
  ) {
    final out = <PromoModel>[];
    for (final d in docs) {
      final data = d.data();
      final b64 = (data['imageB64'] as String?)?.trim() ?? "";
      if (b64.isEmpty) continue;
      final createdAt = data['createdAt'] as Timestamp?;
      out.add(
        PromoModel(
          title: "Promotion",
          imagePath: "b64:$b64",
          stallName: stallName,
          createdAtMs: createdAt?.millisecondsSinceEpoch ?? 0,
        ),
      );
    }
    return out;
  }

  Future<List<PromoModel>> _fetchPromosFromKnownFoodcourts() async {
    final out = <PromoModel>[];
    for (final fcId in _knownFoodCourtIds) {
      final stallsSnap = await FirebaseFirestore.instance
          .collection('foodcourts')
          .doc(fcId)
          .collection('stalls')
          .get();
      for (final stallDoc in stallsSnap.docs) {
        final stallData = stallDoc.data();
        final stallName =
            ((stallData['stallName'] as String?) ??
                    (stallData['businessName'] as String?) ??
                    (stallData['displayName'] as String?))
                ?.trim();
        final promoSnap = await stallDoc.reference
            .collection('promos')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();
        out.addAll(_promosFromDocs(promoSnap.docs, stallName ?? "Stall"));
      }
    }
    out.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return out;
  }

  StallModel _stallFromData(String uid, Map<String, dynamic> data) {
    final stallName =
        ((data['stallName'] as String?) ??
                (data['businessName'] as String?) ??
                (data['displayName'] as String?))
            ?.trim();
    final stallNo =
        ((data['stallNo'] as String?) ?? (data['stallNumber'] as String?))
            ?.trim();
    final stallLocation =
        ((data['stallLocation'] as String?) ?? (data['location'] as String?))
            ?.trim() ??
        "";

    final isHalal =
        (data['isHalal'] as bool?) ?? (data['halalStatus'] as bool?) ?? false;
    final stallTag = (data['stallTag'] as String?)?.trim();
    final vendorStatus = ((data['vendorStatus'] as String?) ?? "UNKNOWN")
        .trim();
    final queueStatus = (data['queueStatus'] as String?)?.trim() ?? "NO_QUEUE";
    final paynowQrUrl = data['paynowQrUrl'] as String?;
    final stallPhotoB64 =
        (data['stallPhotoB64'] as String?)?.trim() ??
        (data['stallphotoB64'] as String?)?.trim();

    final placeId = _placeIdFromData(data, stallLocation);
    final placeName = _placeNameFromPlaceId(placeId);

    final tags = <String>{};
    if (isHalal) tags.add("Halal");
    if (stallTag != null && stallTag.isNotEmpty) tags.add(stallTag);

    final shortDescParts = <String>[];
    if (stallNo != null && stallNo.isNotEmpty) {
      shortDescParts.add("Stall $stallNo");
    }
    if (stallTag != null && stallTag.isNotEmpty) shortDescParts.add(stallTag);
    if (isHalal) shortDescParts.add("Halal");
    if (shortDescParts.isEmpty) shortDescParts.add("Tap to view menu");

    return StallModel(
      id: uid,
      name: (stallName == null || stallName.isEmpty)
          ? "Vendor Stall"
          : stallName,
      stallNo: stallNo,
      placeId: placeId,
      stallDocId: (data['stallDocId'] as String?)?.trim(),
      placeName: placeName,
      shortDesc: shortDescParts.join(" - "),
      rating: 4.2,
      tags: tags,
      vendorStatus: vendorStatus,
      queueStatus: queueStatus,
      isHalal: isHalal,
      paynowQrUrl: paynowQrUrl,
      stallPhotoB64: stallPhotoB64,
    );
  }

  String _placeIdFromData(Map<String, dynamic> data, String stallLocation) {
    final foodCourtId =
        ((data['foodCourtId'] as String?) ?? (data['foodcourtId'] as String?))
            ?.trim();
    if (foodCourtId != null && foodCourtId.isNotEmpty) {
      return _normalizePlaceId(foodCourtId);
    }

    final foodcourtNo =
        (data['foodcourtNo'] as num?)?.toInt() ??
        (data['foodCourtNo'] as num?)?.toInt();
    if (foodcourtNo != null && foodcourtNo >= 1 && foodcourtNo <= 6) {
      return 'fc$foodcourtNo';
    }

    return _placeIdFromLocation(stallLocation);
  }

  String _normalizePlaceId(String rawId) {
    final compact = rawId.toLowerCase().trim().replaceAll(RegExp(r'[\s_-]+'), '');

    if (compact == 'moberlycafe' || compact == 'moberly' || compact == 'cafe1' || compact == 'cafe2') {
      return 'moberly_cafe';
    }
    if (compact == 'oldchangkee' || compact == 'ock') {
      return 'old_chang_kee';
    }
    if (compact == 'fc1' || compact == 'foodcourt1') return 'fc1';
    if (compact == 'fc2' || compact == 'foodcourt2') return 'fc2';
    if (compact == 'fc3' || compact == 'foodcourt3') return 'fc3';
    if (compact == 'fc4' || compact == 'foodcourt4') return 'fc4';
    if (compact == 'fc5' || compact == 'foodcourt5') return 'fc5';
    if (compact == 'fc6' || compact == 'foodcourt6') return 'fc6';
    return rawId;
  }

  String _placeIdFromLocation(String location) {
    final raw = location.toLowerCase();
    final compact = raw.replaceAll(RegExp(r'[\s_-]+'), '');

    if (compact.contains('foodcourt1') || compact.contains('fc1')) return 'fc1';
    if (compact.contains('foodcourt2') || compact.contains('fc2')) return 'fc2';
    if (compact.contains('foodcourt3') || compact.contains('fc3')) return 'fc3';
    if (compact.contains('foodcourt4') || compact.contains('fc4')) return 'fc4';
    if (compact.contains('foodcourt5') || compact.contains('fc5')) return 'fc5';
    if (compact.contains('foodcourt6') || compact.contains('fc6')) return 'fc6';
    if (compact.contains('moberly') || compact.contains('cafe1') || compact.contains('cafe2')) {
      return 'moberly_cafe';
    }
    if (compact.contains('oldchangkee') || compact.contains('ock')) {
      return 'old_chang_kee';
    }
    return 'all';
  }

  String _placeNameFromPlaceId(String placeId) {
    switch (placeId.toLowerCase()) {
      case 'fc1':
        return 'Food Court 1';
      case 'fc2':
        return 'Food Court 2';
      case 'fc3':
        return 'Food Court 3';
      case 'fc4':
        return 'Food Court 4';
      case 'fc5':
        return 'Food Court 5';
      case 'fc6':
        return 'Food Court 6';
      case 'moberly_cafe':
      case 'cafe1':
      case 'cafe2':
      case 'moberly':
        return 'Moberly Cafe';
      case 'old_chang_kee':
      case 'ock':
        return 'Old Chang Kee';
      default:
        return 'All places';
    }
  }

  bool get anyTagSelected => tagFilters.values.any((v) => v);
  List<String> get selectedTags =>
      tagFilters.entries.where((e) => e.value).map((e) => e.key).toList();

  String get selectedPlaceLabel {
    if (selectedPlaceId == null || selectedPlaceId == "all") {
      return "All places";
    }
    final p = places.firstWhere(
      (x) => x.id == selectedPlaceId,
      orElse: () => places.first,
    );
    return p.name;
  }

  void _clearPlace() => setState(() => selectedPlaceId = null);
  void _clearTags() => setState(() {
    for (final k in tagFilters.keys) {
      tagFilters[k] = false;
    }
  });

  void _goToStallsWithPlace(String placeId) {
    setState(() {
      selectedPlaceId = placeId;
      index = 1;
    });
  }

  void _openMenu(StallModel stall) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConsumerMenuPage(stall: stall, onAddToCart: _addToCart),
      ),
    );
  }

  void _addToCart(ConsumerOrder order) {
    setState(() => orders.insert(0, order));
    _snack("Added to cart");
  }

  Future<void> _createOrderInTopLevelOrders(ConsumerOrder order) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final vendorUid = order.vendorUid?.trim() ?? "";
    if (vendorUid.isEmpty) return;

    await FirebaseFirestore.instance.collection('orders').add({
      'stallUid': vendorUid,
      'stallName': order.stallName,
      'placeName': order.placeName,
      'consumerUid': user.uid,
      'consumerName': user.displayName ?? user.email ?? "Customer",
      'itemCount': order.itemCount,
      'total': order.total,
      'status': 'PLACED',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _markOrderPickedUp(String orderId) async {
    await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
      'status': 'PICKED_UP',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() {
      final idx = orders.indexWhere((o) => o.id == orderId);
      if (idx != -1) {
        orders[idx] = orders[idx].copyWith(status: OrderStatus.pickedUp);
      }
    });

    _snack("Marked as picked up");
  }

  Future<void> _submitReview({
    required StallModel stall,
    required int rating,
    required String comment,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Not logged in");
    if (stall.placeId.trim().isEmpty || stall.placeId == 'all') {
      throw Exception("Invalid foodcourt for this stall.");
    }

    final stallDocId = (stall.stallDocId?.trim().isNotEmpty ?? false)
        ? stall.stallDocId!.trim()
        : stall.id;

    await FirebaseFirestore.instance
        .collection('foodcourts')
        .doc(stall.placeId)
        .collection('stalls')
        .doc(stallDocId)
        .collection('reviews')
        .add({
          'stallUid': stall.id,
          'stallDocId': stallDocId,
          'stallName': stall.name,
          'placeId': stall.placeId,
          'placeName': stall.placeName,
          'userUid': user.uid,
          'userName': user.displayName ?? user.email ?? "Student",
          'rating': rating,
          'comment': comment,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  void _proceedToPayment(String orderId) {
    final order = orders.firstWhere((o) => o.id == orderId);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Text(
            "Scan to pay",
            style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                "assets/img/paylah.png",
                width: 220,
                height: 220,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 10),
              Text(
                "Pay for ${order.stallName}",
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "S\$${order.total.toStringAsFixed(2)}",
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900,
                  color: kPink,
                ),
              ),
            ],
          ),
        );
      },
    );

    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      Navigator.pop(context);

      try {
        await _createOrderInTopLevelOrders(order);
      } catch (e) {
        _snack("Order sync failed: $e");
      }

      if (!mounted) return;

      setState(() {
        final idx = orders.indexWhere((o) => o.id == orderId);
        if (idx != -1) {
          orders[idx] = orders[idx].copyWith(status: OrderStatus.placed);
        }
      });
      _snack("Payment received - Order sent to vendor");
    });
  }

  @override
  Widget build(BuildContext context) {
    final homePlaces = places.where((p) => p.id != "all").toList();

    return StreamBuilder<List<StallModel>>(
      stream: _vendorStallsStream(),
      builder: (context, snap) {
        final dbStalls = snap.hasError
            ? const <StallModel>[]
            : (snap.data ?? const <StallModel>[]);

        return StreamBuilder<List<PromoModel>>(
          stream: _promosStream(),
          builder: (context, promoSnap) {
            final dbPromos = promoSnap.data ?? promos;

            final filtered = dbStalls.where((s) {
              final placeOk =
                  (selectedPlaceId == null || selectedPlaceId == "all")
                  ? true
                  : s.placeId == selectedPlaceId;
              if (!placeOk) return false;

              if (anyTagSelected) {
                final stallTagsLower = s.tags
                    .map((x) => x.toLowerCase())
                    .toSet();
                for (final t in selectedTags) {
                  if (!stallTagsLower.contains(t.toLowerCase())) return false;
                }
              }

              final q = searchCtrl.text.trim().toLowerCase();
              if (q.isNotEmpty) {
                final hay = "${s.name} ${s.placeName} ${s.shortDesc}"
                    .toLowerCase();
                if (!hay.contains(q)) return false;
              }
              return true;
            }).toList();

            final pages = [
              ConsumerHomeTab(
                promos: dbPromos,
                places: homePlaces,
                selectedPlaceId: selectedPlaceId,
                tagFilters: tagFilters,
                searchCtrl: searchCtrl,
                onSearchChanged: () => setState(() {}),
                onSelectTagChip: (tag) => setState(
                  () => tagFilters[tag] = !(tagFilters[tag] ?? false),
                ),
                onClearPlace: _clearPlace,
                onClearTags: _clearTags,
                selectedPlaceLabel: selectedPlaceLabel,
                anyTagSelected: anyTagSelected,
                selectedTags: selectedTags,
                onTapPlaceCard: _goToStallsWithPlace,
                stallsFoundCount: filtered.length,
                crowdStalls: filtered.take(8).toList(),
                previewStalls: filtered.take(2).toList(),
                onTapPreviewStall: _openMenu,
                onViewAllStalls: () => setState(() => index = 1),
              ),
              ConsumerStallsTab(
                placeCards: homePlaces,
                selectedPlaceId: selectedPlaceId,
                tagFilters: tagFilters,
                searchCtrl: searchCtrl,
                onSearchChanged: () => setState(() {}),
                onClearPlace: _clearPlace,
                onClearTags: _clearTags,
                selectedPlaceLabel: selectedPlaceLabel,
                anyTagSelected: anyTagSelected,
                selectedTags: selectedTags,
                filteredStalls: filtered,
                onTapPlaceCard: (placeId) =>
                    setState(() => selectedPlaceId = placeId),
                onTapStall: _openMenu,
                onSelectTagChip: (tag) => setState(
                  () => tagFilters[tag] = !(tagFilters[tag] ?? false),
                ),
              ),
              ConsumerOrdersTab(
                localOrders: orders,
                onProceedPayment: _proceedToPayment,
                onMarkPickedUp: (id, data) async {
                  try {
                    await _markOrderPickedUp(id);
                  } catch (e) {
                    _snack("Pick up failed: $e");
                  }
                },
              ),
              ConsumerReviewsTab(
                stalls: dbStalls,
                onSubmitReview: (stall, rating, comment) async {
                  await _submitReview(
                    stall: stall,
                    rating: rating,
                    comment: comment,
                  );
                },
              ),
              const ConsumerMapsTab(),
            ];

            return Scaffold(
              backgroundColor: kBgSoft,
              body: pages[index],
              bottomNavigationBar: NavigationBar(
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
                    icon: Icon(Icons.storefront_outlined),
                    selectedIcon: Icon(Icons.storefront),
                    label: "Stalls",
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: "Orders",
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.reviews_outlined),
                    selectedIcon: Icon(Icons.reviews),
                    label: "Reviews",
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map),
                    label: "Maps",
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class ConsumerHomeTab extends StatelessWidget {
  final List<PromoModel> promos;
  final List<PlaceModel> places;

  final String? selectedPlaceId;
  final Map<String, bool> tagFilters;
  final TextEditingController searchCtrl;
  final VoidCallback onSearchChanged;

  final void Function(String tag) onSelectTagChip;
  final VoidCallback onClearPlace;
  final VoidCallback onClearTags;

  final String selectedPlaceLabel;
  final bool anyTagSelected;
  final List<String> selectedTags;

  final void Function(String placeId) onTapPlaceCard;

  final int stallsFoundCount;
  final List<StallModel> crowdStalls;
  final List<StallModel> previewStalls;
  final void Function(StallModel stall) onTapPreviewStall;
  final VoidCallback onViewAllStalls;

  const ConsumerHomeTab({
    super.key,
    required this.promos,
    required this.places,
    required this.selectedPlaceId,
    required this.tagFilters,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.onSelectTagChip,
    required this.onClearPlace,
    required this.onClearTags,
    required this.selectedPlaceLabel,
    required this.anyTagSelected,
    required this.selectedTags,
    required this.onTapPlaceCard,
    required this.stallsFoundCount,
    required this.crowdStalls,
    required this.previewStalls,
    required this.onTapPreviewStall,
    required this.onViewAllStalls,
  });

  static const Color kPink = Color(0xFFFF3D8D);
  static const Color kBgSoft = Color(0xFFFFF1F6);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          _HeaderRow(),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                  color: Colors.black.withOpacity(0.06),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.black45),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: (_) => onSearchChanged(),
                    decoration: InputDecoration(
                      hintText: "Search stalls, cuisines...",
                      hintStyle: GoogleFonts.manrope(
                        color: Colors.black38,
                        fontWeight: FontWeight.w700,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          if (promos.isNotEmpty)
            SizedBox(
              height: 148,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: promos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) =>
                    SizedBox(width: 320, child: _PromoCard(promo: promos[i])),
              ),
            ),

          const SizedBox(height: 14),

          _FilterSummaryRow(
            selectedPlaceLabel: selectedPlaceLabel,
            anyTagSelected: anyTagSelected,
            selectedTags: selectedTags,
            onClearPlace: onClearPlace,
            onClearTags: onClearTags,
          ),

          const SizedBox(height: 10),

          _TagChipsRow(tagFilters: tagFilters, onTap: onSelectTagChip),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Live crowd level",
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                selectedPlaceLabel,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (crowdStalls.isEmpty)
            const _EmptyCard(
              title: "No crowd data yet",
              subtitle:
                  "Stalls will appear here when queue status is available.",
            )
          else
            SizedBox(
              height: 164,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: crowdStalls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _LiveCrowdCard(stall: crowdStalls[i]),
              ),
            ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Nearby places",
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                "$stallsFoundCount stalls",
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  color: kPink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          SizedBox(
            height: 155,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: places.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final p = places[i];
                final selected = selectedPlaceId == p.id;

                return InkWell(
                  onTap: () => onTapPlaceCard(p.id),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 210,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected ? kPink : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                          color: Colors.black.withOpacity(0.08),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          buildAnyImage(
                            p.imagePath,
                            w: double.infinity,
                            h: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.88),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    p.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Popular stalls",
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              TextButton(
                onPressed: onViewAllStalls,
                child: Text(
                  "View all",
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    color: kPink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (previewStalls.isEmpty)
            _EmptyCard(
              title: "No stalls yet",
              subtitle: "Try clearing filters or pick another foodcourt.",
            )
          else
            Column(
              children: previewStalls
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _StallCard(
                        stall: s,
                        onTap: () => onTapPreviewStall(s),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  static const Color kPink = Color(0xFFFF3D8D);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kPink.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.local_dining, color: kPink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Discover foods you will love 🍱",
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                "order food from SPeats",
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomePage()),
                  (_) => false,
                );
              }
            },
            icon: const Icon(Icons.logout, size: 18),
            label: Text(
              "Logout",
              style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: const BorderSide(color: Color(0xFFEAEAEA)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _PromoCard extends StatelessWidget {
  final PromoModel promo;
  const _PromoCard({required this.promo});

  static const Color kPink = Color(0xFFFF3D8D);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 148,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.08),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            buildAnyImageFlexible(
              promo.imagePath,
              w: double.infinity,
              h: double.infinity,
              fit: BoxFit.cover,
            ),
            Positioned(
              left: 14,
              top: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_offer, color: kPink, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      promo.title,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 190),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.52),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  promo.stallName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
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

class _FilterSummaryRow extends StatelessWidget {
  final String selectedPlaceLabel;
  final bool anyTagSelected;
  final List<String> selectedTags;
  final VoidCallback onClearPlace;
  final VoidCallback onClearTags;

  const _FilterSummaryRow({
    required this.selectedPlaceLabel,
    required this.anyTagSelected,
    required this.selectedTags,
    required this.onClearPlace,
    required this.onClearTags,
  });

  static const Color kPink = Color(0xFFFF3D8D);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Pill(
          text: selectedPlaceLabel,
          icon: Icons.place,
          onClear: selectedPlaceLabel == "All places" ? null : onClearPlace,
        ),
        if (anyTagSelected)
          _Pill(
            text: selectedTags.join(", "),
            icon: Icons.filter_alt,
            onClear: onClearTags,
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onClear;

  const _Pill({required this.text, required this.icon, required this.onClear});

  static const Color kPink = Color(0xFFFF3D8D);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kPink.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: kPink),
          const SizedBox(width: 6),
          Text(text, style: GoogleFonts.manrope(fontWeight: FontWeight.w900)),
          if (onClear != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onClear,
              child: const Icon(Icons.close, size: 18, color: Colors.black45),
            ),
          ],
        ],
      ),
    );
  }
}

class _TagChipsRow extends StatelessWidget {
  final Map<String, bool> tagFilters;
  final void Function(String tag) onTap;

  const _TagChipsRow({required this.tagFilters, required this.onTap});

  static const Color kPink = Color(0xFFFF3D8D);

  @override
  Widget build(BuildContext context) {
    final tags = tagFilters.keys.toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tags.map((t) {
          final selected = tagFilters[t] ?? false;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              label: Text(
                t,
                style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
              ),
              onSelected: (_) => onTap(t),
              selectedColor: kPink.withOpacity(0.18),
              backgroundColor: Colors.white,
              side: BorderSide(color: selected ? kPink : Colors.black12),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class ConsumerStallsTab extends StatelessWidget {
  final List<PlaceModel> placeCards;
  final String? selectedPlaceId;

  final Map<String, bool> tagFilters;
  final TextEditingController searchCtrl;
  final VoidCallback onSearchChanged;

  final VoidCallback onClearPlace;
  final VoidCallback onClearTags;

  final String selectedPlaceLabel;
  final bool anyTagSelected;
  final List<String> selectedTags;

  final List<StallModel> filteredStalls;

  final void Function(String placeId) onTapPlaceCard;
  final void Function(StallModel stall) onTapStall;
  final void Function(String tag) onSelectTagChip;

  const ConsumerStallsTab({
    super.key,
    required this.placeCards,
    required this.selectedPlaceId,
    required this.tagFilters,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.onClearPlace,
    required this.onClearTags,
    required this.selectedPlaceLabel,
    required this.anyTagSelected,
    required this.selectedTags,
    required this.filteredStalls,
    required this.onTapPlaceCard,
    required this.onTapStall,
    required this.onSelectTagChip,
  });

  static const Color kPink = Color(0xFFFF3D8D);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        children: [
          Row(
            children: [
              Text(
                "Stalls",
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                "${filteredStalls.length} found",
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900,
                  color: kPink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: placeCards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final p = placeCards[i];
                final selected = selectedPlaceId == p.id;

                return InkWell(
                  onTap: () => onTapPlaceCard(p.id),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected ? kPink : Colors.black12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: buildAnyImage(
                            p.imagePath,
                            w: 30,
                            h: 30,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p.name,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                  color: Colors.black.withOpacity(0.06),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.black45),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: (_) => onSearchChanged(),
                    decoration: InputDecoration(
                      hintText: "Search stalls...",
                      hintStyle: GoogleFonts.manrope(
                        color: Colors.black38,
                        fontWeight: FontWeight.w700,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                  ),
                ),
                if (searchCtrl.text.trim().isNotEmpty)
                  IconButton(
                    onPressed: () {
                      searchCtrl.clear();
                      onSearchChanged();
                    },
                    icon: const Icon(Icons.close, color: Colors.black45),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _FilterSummaryRow(
            selectedPlaceLabel: selectedPlaceLabel,
            anyTagSelected: anyTagSelected,
            selectedTags: selectedTags,
            onClearPlace: onClearPlace,
            onClearTags: onClearTags,
          ),

          const SizedBox(height: 10),

          _TagChipsRow(tagFilters: tagFilters, onTap: onSelectTagChip),

          const SizedBox(height: 14),

          if (filteredStalls.isEmpty)
            const _EmptyCard(
              title: "No stalls found",
              subtitle: "Try clearing filters or select another foodcourt.",
            )
          else
            Column(
              children: filteredStalls
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _StallCard(stall: s, onTap: () => onTapStall(s)),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.info_outline, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StallCard extends StatelessWidget {
  final StallModel stall;
  final VoidCallback onTap;

  const _StallCard({required this.stall, required this.onTap});

  static const Color kPink = Color(0xFFFF3D8D);

  @override
  Widget build(BuildContext context) {
    final photoSrc = (stall.stallPhotoB64 ?? "").trim();

    final statusChip = stall.queueStatus.toUpperCase() == "OPEN"
        ? _MiniChip(text: "Queue Open", bg: kPink.withOpacity(0.16), fg: kPink)
        : _MiniChip(
            text: "No Queue",
            bg: Colors.black.withOpacity(0.06),
            fg: Colors.black54,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 10),
              color: Colors.black.withOpacity(0.08),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: kPink.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: photoSrc.isEmpty
                    ? const Icon(Icons.storefront, color: kPink)
                    : buildAnyImageFlexible(
                        photoSrc,
                        w: 58,
                        h: 58,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stall.name,
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "${stall.placeName} - ${stall.shortDesc}",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      statusChip,
                      ...stall.tags
                          .take(3)
                          .map(
                            (t) => _MiniChip(
                              text: t,
                              bg: Colors.black.withOpacity(0.06),
                              fg: Colors.black87,
                            ),
                          ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;

  const _MiniChip({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w900,
          color: fg,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _LiveCrowdCard extends StatelessWidget {
  const _LiveCrowdCard({required this.stall});
  final StallModel stall;

  ({String faceAsset, String label, String etaLabel, Color color}) _crowdUi(
    String queueStatus,
  ) {
    final s = queueStatus.trim().toUpperCase();
    if (s == "VERY_BUSY") {
      return (
        faceAsset: "assets/img/red.png",
        label: "Crowded",
        etaLabel: "EST 30 min",
        color: Colors.red,
      );
    }
    if (s == "MODERATE") {
      return (
        faceAsset: "assets/img/yellow.png",
        label: "Medium",
        etaLabel: "EST 15 min",
        color: const Color(0xFFE0A100),
      );
    }
    return (
      faceAsset: "assets/img/green.png",
      label: "No crowd",
      etaLabel: "EST 5 min",
      color: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = _crowdUi(stall.queueStatus);

    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildAnyImage(ui.faceAsset, w: 22, h: 22, fit: BoxFit.contain),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ui.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: ui.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stall.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          Text(
            stall.placeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const Spacer(),
          Text(
            ui.etaLabel,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class ConsumerOrdersTab extends StatelessWidget {
  const ConsumerOrdersTab({
    super.key,
    required this.localOrders,
    required this.onProceedPayment,
    required this.onMarkPickedUp,
  });

  static const Color kPink = Color(0xFFFF3D8D);

  final List<ConsumerOrder> localOrders;
  final void Function(String orderId) onProceedPayment;
  final Future<void> Function(String orderId, Map<String, dynamic> orderData)
  onMarkPickedUp;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    final pendingLocal = localOrders
        .where((o) => o.status == OrderStatus.pendingPayment)
        .toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        children: [
          Text(
            "Orders",
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Checkout items first. Vendor will see your paid orders.",
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 14),

          _SectionHeader(title: "Checkout", count: pendingLocal.length),
          const SizedBox(height: 10),

          if (pendingLocal.isEmpty)
            const _EmptyCard(
              title: "Cart is empty",
              subtitle: "Add items from a stall menu.",
            )
          else
            Column(
              children: pendingLocal
                  .map(
                    (o) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CheckoutCard(
                        order: o,
                        onProceed: () => onProceedPayment(o.id),
                      ),
                    ),
                  )
                  .toList(),
            ),

          const SizedBox(height: 16),

          _SectionHeader(title: "Paid orders", count: null),
          const SizedBox(height: 10),

          if (uid == null)
            const _EmptyCard(
              title: "Not logged in",
              subtitle: "Please login again.",
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('consumerUid', isEqualTo: uid)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _EmptyCard(
                    title: "Orders failed to load",
                    subtitle: "${snap.error}",
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final docs = [...(snap.data?.docs ?? [])];
                docs.sort((a, b) {
                  final at = a.data()['createdAt'] as Timestamp?;
                  final bt = b.data()['createdAt'] as Timestamp?;
                  final ams = at?.millisecondsSinceEpoch ?? 0;
                  final bms = bt?.millisecondsSinceEpoch ?? 0;
                  return bms.compareTo(ams);
                });
                if (docs.isEmpty) {
                  return const _EmptyCard(
                    title: "No paid orders yet",
                    subtitle: "After payment, your order will appear here.",
                  );
                }

                return Column(
                  children: docs.map((d) {
                    final data = d.data();
                    final stallName = (data['stallName'] as String?) ?? "Stall";
                    final placeName = (data['placeName'] as String?) ?? "Place";
                    final rawStatus = (data['status'] as String?) ?? "PLACED";
                    final displayNo = (data['displayNo'] as num?)?.toInt();
                    final total = (data['total'] as num?)?.toDouble() ?? 0.0;
                    final itemCount = (data['itemCount'] as num?)?.toInt() ?? 1;

                    final normalized = rawStatus
                        .trim()
                        .toUpperCase()
                        .replaceAll(' ', '_');
                    final isReady = normalized == "READY";
                    final isPickedUp =
                        normalized == "PICKED_UP" || normalized == "PICKEDUP";
                    final label = isPickedUp
                        ? "PICKED UP"
                        : (isReady ? "READY" : "PLACED");
                    final chipColor = isPickedUp
                        ? Colors.grey
                        : (isReady ? Colors.green : kPink);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PaidOrderCard(
                        title: displayNo != null
                            ? "Order #$displayNo"
                            : "Order",
                        subtitle: "$stallName - $placeName",
                        trailingLabel: label,
                        trailingColor: chipColor,
                        details:
                            "$itemCount items - S\$${total.toStringAsFixed(2)}",
                        onPrimary: isReady
                            ? () async => onMarkPickedUp(d.id, data)
                            : null,
                        primaryText: isReady ? "Mark picked up" : null,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        if (count != null)
          Text(
            "$count",
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w900,
              color: Colors.black45,
            ),
          ),
      ],
    );
  }
}

class _CheckoutCard extends StatelessWidget {
  const _CheckoutCard({required this.order, required this.onProceed});
  static const Color kPink = Color(0xFFFF3D8D);

  final ConsumerOrder order;
  final VoidCallback onProceed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.08),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kPink.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.shopping_bag, color: kPink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.stallName,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.placeName,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${order.itemCount} item(s) - S\$${order.total.toStringAsFixed(2)}",
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: kPink.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "PAY",
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    color: kPink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onProceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                "Proceed to payment",
                style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaidOrderCard extends StatelessWidget {
  const _PaidOrderCard({
    required this.title,
    required this.subtitle,
    required this.trailingLabel,
    required this.trailingColor,
    required this.details,
    required this.onPrimary,
    required this.primaryText,
  });

  final String title;
  final String subtitle;
  final String trailingLabel;
  final Color trailingColor;
  final String details;
  final VoidCallback? onPrimary;
  final String? primaryText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.08),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: trailingColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.receipt_long, color: trailingColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: trailingColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  trailingLabel,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    color: trailingColor,
                  ),
                ),
              ),
            ],
          ),
          if (onPrimary != null && primaryText != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: trailingColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  primaryText!,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ConsumerReviewsTab extends StatefulWidget {
  const ConsumerReviewsTab({
    super.key,
    required this.stalls,
    required this.onSubmitReview,
  });
  final List<StallModel> stalls;
  final Future<void> Function(StallModel stall, int rating, String comment)
  onSubmitReview;

  @override
  State<ConsumerReviewsTab> createState() => _ConsumerReviewsTabState();
}

class _ConsumerReviewsTabState extends State<ConsumerReviewsTab> {
  final _reviewCtrl = TextEditingController();
  int _rating = 0;
  String? _selectedStallName;

  static const Color kPink = Color(0xFFFF3D8D);

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return "just now";
    final now = DateTime.now();
    final dt = ts.toDate();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return "just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    if (diff.inDays < 7) return "${diff.inDays}d ago";
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 5) return "${weeks}w ago";
    final months = (diff.inDays / 30).floor();
    if (months < 12) return "${months}mo ago";
    final years = (diff.inDays / 365).floor();
    return "${years}y ago";
  }

  Stream<List<_RecentReviewItem>> _recentReviewsStream() async* {
    yield await _fetchRecentReviews();
    yield* Stream.periodic(
      const Duration(seconds: 6),
    ).asyncMap((_) => _fetchRecentReviews());
  }

  Future<List<_RecentReviewItem>> _fetchRecentReviews() async {
    final out = <_RecentReviewItem>[];
    final seen = <String>{};
    final jobs = <Future<List<_RecentReviewItem>>>[];

    for (final stall in widget.stalls) {
      final placeId = stall.placeId.trim();
      if (placeId.isEmpty || placeId == "all") continue;

      final stallDocId = (stall.stallDocId?.trim().isNotEmpty ?? false)
          ? stall.stallDocId!.trim()
          : stall.id.trim();
      if (stallDocId.isEmpty) continue;

      final key = "$placeId::$stallDocId";
      if (!seen.add(key)) continue;
      jobs.add(_fetchReviewsForStall(placeId, stallDocId, stall));
    }

    if (jobs.isNotEmpty) {
      final all = await Future.wait(jobs);
      for (final list in all) {
        out.addAll(list);
      }
    }

    out.sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });

    if (out.length > 7) return out.sublist(0, 7);
    return out;
  }

  Future<List<_RecentReviewItem>> _fetchReviewsForStall(
    String placeId,
    String stallDocId,
    StallModel stall,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('foodcourts')
          .doc(placeId)
          .collection('stalls')
          .doc(stallDocId)
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .get()
          .timeout(const Duration(seconds: 4));

      final out = <_RecentReviewItem>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final ratingNum = (data['rating'] as num?)?.toInt() ?? 0;
        out.add(
          _RecentReviewItem(
            stallName: ((data['stallName'] as String?) ?? stall.name).trim().isEmpty
                ? "Stall"
                : ((data['stallName'] as String?) ?? stall.name).trim(),
            placeName: ((data['placeName'] as String?) ?? stall.placeName).trim(),
            userName: ((data['userName'] as String?) ?? "Student").trim().isEmpty
                ? "Student"
                : ((data['userName'] as String?) ?? "Student").trim(),
            comment: ((data['comment'] as String?) ?? "").trim(),
            rating: ratingNum.clamp(1, 5),
            createdAt: data['createdAt'] as Timestamp?,
          ),
        );
      }
      return out;
    } catch (_) {
      // Skip this stall if reviews path/index/rules are unavailable.
      return const <_RecentReviewItem>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final stallsByName = <String, StallModel>{};
    for (final s in widget.stalls) {
      final key = s.name.trim();
      if (key.isEmpty) continue;
      stallsByName.putIfAbsent(key, () => s);
    }
    final stallNames = stallsByName.keys.toList()..sort();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        children: [
          Text(
            "Reviews",
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                  color: Colors.black.withOpacity(0.08),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Leave a review",
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  initialValue: _selectedStallName,
                  isExpanded: true,
                  items: stallNames
                      .map(
                        (name) => DropdownMenuItem<String>(
                          value: name,
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: stallNames.isEmpty
                      ? null
                      : (v) => setState(() => _selectedStallName = v),
                  decoration: InputDecoration(
                    hintText: stallNames.isEmpty
                        ? "No stalls available yet"
                        : "Pick a stall",
                    hintStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: Colors.black38,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Text(
                      "Rating",
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: List.generate(
                        5,
                        (i) => IconButton(
                          onPressed: () => setState(() => _rating = i + 1),
                          icon: Icon(
                            i < _rating ? Icons.star : Icons.star_border,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                TextField(
                  controller: _reviewCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "Write something...",
                    hintStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: Colors.black38,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_selectedStallName == null ||
                          _reviewCtrl.text.trim().isEmpty ||
                          _rating == 0) {
                        _snack("Pick stall, rating and review.");
                        return;
                      }
                      final selected = stallsByName[_selectedStallName!];
                      if (selected == null) {
                        _snack("Selected stall not found.");
                        return;
                      }
                      try {
                        await widget.onSubmitReview(
                          selected,
                          _rating,
                          _reviewCtrl.text.trim(),
                        );
                      } catch (e) {
                        _snack("Review submit failed: $e");
                        return;
                      }
                      _snack("Saved review for $_selectedStallName");
                      _reviewCtrl.clear();
                      setState(() {
                        _rating = 0;
                        _selectedStallName = null;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      "Submit",
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          Text(
            "Other reviews",
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<_RecentReviewItem>>(
            stream: _recentReviewsStream(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _EmptyCard(
                  title: "Reviews failed to load",
                  subtitle: "${snap.error}",
                );
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink();
              }

              final reviews = snap.data ?? const <_RecentReviewItem>[];
              if (reviews.isEmpty) {
                return const _EmptyCard(
                  title: "No reviews yet",
                  subtitle: "Be the first to leave a review.",
                );
              }

              return Column(
                children: reviews.map((r) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: kPink.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: kPink,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.stallName,
                                      style: GoogleFonts.manrope(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      r.placeName.isEmpty
                                          ? "by ${r.userName}"
                                          : "${r.placeName} - by ${r.userName}",
                                      style: GoogleFonts.manrope(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _timeAgo(r.createdAt),
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                i < r.rating ? Icons.star : Icons.star_border,
                                color: Colors.orange,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            r.comment.isEmpty
                                ? "No comment provided."
                                : r.comment,
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
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

class ConsumerMapsTab extends StatefulWidget {
  const ConsumerMapsTab({super.key});

  static const Color kPink = Color(0xFFFF3D8D);

  @override
  State<ConsumerMapsTab> createState() => _ConsumerMapsTabState();
}

class _ConsumerMapsTabState extends State<ConsumerMapsTab> {
  static const LatLng _sp = LatLng(1.3099, 103.7773);

  static const List<_CampusSpot> _spots = [
    _CampusSpot(
      id: "fc1",
      title: "Food Court 1",
      latLng: LatLng(1.3110, 103.7786),
    ),
    _CampusSpot(
      id: "fc2",
      title: "Food Court 2",
      latLng: LatLng(1.3095, 103.7764),
    ),
    _CampusSpot(
      id: "fc3",
      title: "Food Court 3",
      latLng: LatLng(1.3089, 103.7782),
    ),
    _CampusSpot(
      id: "fc4",
      title: "Food Court 4",
      latLng: LatLng(1.3099, 103.7791),
    ),
    _CampusSpot(
      id: "fc5",
      title: "Food Court 5",
      latLng: LatLng(1.3112, 103.7774),
    ),
    _CampusSpot(
      id: "fc6",
      title: "Food Court 6",
      latLng: LatLng(1.3086, 103.7769),
    ),
    _CampusSpot(
      id: "moberly",
      title: "Moberly Cafe",
      latLng: LatLng(1.3102, 103.7779),
    ),
    _CampusSpot(
      id: "old_chang_kee",
      title: "Old Chang Kee",
      latLng: LatLng(1.3097, 103.7770),
    ),
  ];

  GoogleMapController? _controller;
  StreamSubscription<Position>? _positionSub;
  LatLng? _userLatLng;
  bool _hasMovedCameraToUser = false;

  Set<Marker> get _markers => {
    const Marker(
      markerId: MarkerId("sp"),
      position: _sp,
      infoWindow: InfoWindow(title: "Singapore Polytechnic"),
    ),
    ..._spots.map(
      (s) => Marker(
        markerId: MarkerId(s.id),
        position: s.latLng,
        infoWindow: InfoWindow(title: s.title),
      ),
    ),
    if (_userLatLng != null)
      Marker(
        markerId: const MarkerId("user"),
        position: _userLatLng!,
        infoWindow: const InfoWindow(title: "You are here"),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ),
      ),
  };

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
  }

  Future<void> _startLocationUpdates() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    try {
      final now = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      _setUserLatLng(LatLng(now.latitude, now.longitude));
    } catch (_) {}

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((position) {
      if (!mounted) return;
      _setUserLatLng(LatLng(position.latitude, position.longitude));
    });
  }

  void _setUserLatLng(LatLng next) {
    setState(() => _userLatLng = next);
    if (!_hasMovedCameraToUser) {
      _hasMovedCameraToUser = true;
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(next, 16.8));
    }
  }

  String _subtitleForSpot(_CampusSpot spot) {
    final user = _userLatLng;
    if (user == null) return "Location unavailable";

    final meters = Geolocator.distanceBetween(
      user.latitude,
      user.longitude,
      spot.latLng.latitude,
      spot.latLng.longitude,
    );

    final etaMinutes = (meters / 80).round().clamp(1, 9999);
    final distanceLabel = meters >= 1000
        ? "${(meters / 1000).toStringAsFixed(2)} km away"
        : "${meters.round()} m away";
    return "$etaMinutes min • $distanceLabel";
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _goTo(LatLng pos) {
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(pos, 18));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        children: [
          Text(
            "Singapore Poly Food Map",
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Find the nearest stall next to you.",
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 280,
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _sp,
                  zoom: 16.8,
                ),
                markers: _markers,
                onMapCreated: (c) => _controller = c,
                myLocationEnabled: _userLatLng != null,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                mapType: MapType.normal,
              ),
            ),
          ),

          const SizedBox(height: 12),
          Text(
            "Jump to",
            style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),

          ..._spots.asMap().entries.map((entry) {
            final i = entry.key;
            final spot = entry.value;
            return Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: _MapInfoRow(
                title: spot.title,
                subtitle: _subtitleForSpot(spot),
                onTap: () => _goTo(spot.latLng),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CampusSpot {
  const _CampusSpot({
    required this.id,
    required this.title,
    required this.latLng,
  });

  final String id;
  final String title;
  final LatLng latLng;
}

class _MapInfoRow extends StatelessWidget {
  const _MapInfoRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const Color kPink = Color(0xFFFF3D8D);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: kPink.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: kPink,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w900,
                      fontSize: 24 / 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: Colors.black45,
                      fontSize: 22 / 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}

class ConsumerMenuPage extends StatelessWidget {
  const ConsumerMenuPage({
    super.key,
    required this.stall,
    required this.onAddToCart,
  });

  static const Color kPink = Color(0xFFFF3D8D);

  final StallModel stall;
  final void Function(ConsumerOrder order) onAddToCart;

  MenuItemModel _menuFromDb(String id, Map<String, dynamic> data) {
    final groupsRaw = (data['optionGroups'] as List?) ?? const [];
    final groups = groupsRaw.map((g) {
      final gm = (g as Map).cast<String, dynamic>();

      final choicesRaw = (gm['choices'] as List?) ?? const [];
      final choices = choicesRaw.map((c) {
        final cm = (c as Map).cast<String, dynamic>();
        return OptionChoice(
          label: (cm['label'] as String?)?.trim().isNotEmpty == true
              ? (cm['label'] as String).trim()
              : "Option",
          extraPrice: (cm['extraPrice'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();

      return OptionGroup(
        title: (gm['title'] as String?)?.trim().isNotEmpty == true
            ? (gm['title'] as String).trim()
            : "Options",
        maxSelect: (gm['maxSelect'] as num?)?.toInt() ?? 1,
        choices: choices,
      );
    }).toList();

    final rawImage =
        (data['imageUrl'] as String?) ?? (data['imagePath'] as String?) ?? "";

    return MenuItemModel(
      id: id,
      name: ((data['name'] as String?) ?? "Untitled").trim(),
      desc: ((data['subtitle'] as String?) ?? (data['desc'] as String?) ?? "")
          .trim(),
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      imagePath: rawImage.trim(),
      optionGroups: groups,
      soldOut: (data['soldOut'] as bool?) ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canUsePublic = stall.placeId.isNotEmpty && stall.placeId != "all";
    final publicStallDocId =
        (stall.stallDocId != null && stall.stallDocId!.isNotEmpty)
        ? stall.stallDocId!
        : stall.id;

    final publicMenuRef = canUsePublic
        ? FirebaseFirestore.instance
              .collection('foodcourts')
              .doc(stall.placeId)
              .collection('stalls')
              .doc(publicStallDocId)
              .collection('menuItems')
        : null;

    final privateMenuRef = FirebaseFirestore.instance
        .collection('users')
        .doc(stall.id)
        .collection('menuItems');

    return Scaffold(
      backgroundColor: const Color(0xFFFFF1F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF1F6),
        elevation: 0,
        title: Text(
          stall.name,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            (publicMenuRef?.snapshots()) ??
            privateMenuRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _MenuEmptyState(
              title: "Menu failed to load",
              subtitle: "${snap.error}",
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty && publicMenuRef != null) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: privateMenuRef.snapshots(),
              builder: (context, snap2) {
                if (snap2.hasError) {
                  return _MenuEmptyState(
                    title: "Menu failed to load",
                    subtitle: "${snap2.error}",
                  );
                }
                if (snap2.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs2 = snap2.data?.docs ?? [];
                if (docs2.isEmpty) {
                  return const _MenuEmptyState(
                    title: "No menu items yet",
                    subtitle: "Vendor has not added any menu items.",
                  );
                }
                return _MenuList(
                  items: docs2.map((d) => _menuFromDb(d.id, d.data())).toList(),
                  stall: stall,
                  onAddToCart: onAddToCart,
                );
              },
            );
          }

          if (docs.isEmpty) {
            return const _MenuEmptyState(
              title: "No menu items yet",
              subtitle: "Vendor has not added any menu items.",
            );
          }

          return _MenuList(
            items: docs.map((d) => _menuFromDb(d.id, d.data())).toList(),
            stall: stall,
            onAddToCart: onAddToCart,
          );
        },
      ),
    );
  }
}

class _MenuList extends StatelessWidget {
  const _MenuList({
    required this.items,
    required this.stall,
    required this.onAddToCart,
  });

  static const Color kPink = Color(0xFFFF3D8D);

  final List<MenuItemModel> items;
  final StallModel stall;
  final void Function(ConsumerOrder order) onAddToCart;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final it = items[i];
        final disabled = it.soldOut;

        return Opacity(
          opacity: disabled ? 0.55 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                  color: Colors.black.withOpacity(0.08),
                ),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(18),
                  ),
                  child: buildAnyImageFlexible(
                    it.imagePath,
                    w: 94,
                    h: 94,
                    fit: BoxFit.cover,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                it.name,
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (disabled)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  "SOLD OUT",
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11.5,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          it.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              "S\$${it.price.toStringAsFixed(2)}",
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w900,
                                color: kPink,
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: disabled
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ConsumerCustomizationPage(
                                                item: it,
                                                stall: stall,
                                                onAddToCart: onAddToCart,
                                              ),
                                        ),
                                      );
                                    },
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: disabled
                                      ? Colors.black.withOpacity(0.06)
                                      : kPink.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.add,
                                  color: disabled ? Colors.black38 : kPink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MenuEmptyState extends StatelessWidget {
  const _MenuEmptyState({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConsumerCustomizationPage extends StatefulWidget {
  const ConsumerCustomizationPage({
    super.key,
    required this.item,
    required this.stall,
    required this.onAddToCart,
  });

  final MenuItemModel item;
  final StallModel stall;
  final void Function(ConsumerOrder order) onAddToCart;

  @override
  State<ConsumerCustomizationPage> createState() =>
      _ConsumerCustomizationPageState();
}

class _ConsumerCustomizationPageState extends State<ConsumerCustomizationPage> {
  static const Color kPink = Color(0xFFFF3D8D);

  final Map<String, bool> _selected = {};

  @override
  void initState() {
    super.initState();
    for (final g in widget.item.optionGroups) {
      for (final c in g.choices) {
        _selected["${g.title}|${c.label}"] = false;
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  int _selectedCount(OptionGroup group) {
    int count = 0;
    for (final c in group.choices) {
      if (_selected["${group.title}|${c.label}"] == true) count++;
    }
    return count;
  }

  void _toggleChoice(OptionGroup group, OptionChoice choice, bool value) {
    final key = "${group.title}|${choice.label}";

    if (!value) {
      setState(() => _selected[key] = false);
      return;
    }

    if (group.maxSelect <= 1) {
      setState(() {
        for (final c in group.choices) {
          _selected["${group.title}|${c.label}"] = c.label == choice.label;
        }
      });
      return;
    }

    if (_selectedCount(group) >= group.maxSelect) {
      _snack("Max ${group.maxSelect} selections for ${group.title}");
      return;
    }

    setState(() => _selected[key] = true);
  }

  double _extraTotal() {
    double total = 0;
    for (final g in widget.item.optionGroups) {
      for (final c in g.choices) {
        if (_selected["${g.title}|${c.label}"] == true) total += c.extraPrice;
      }
    }
    return total;
  }

  Map<String, dynamic> _selectedOptionsPayload() {
    final map = <String, List<String>>{};
    for (final g in widget.item.optionGroups) {
      final picked = <String>[];
      for (final c in g.choices) {
        if (_selected["${g.title}|${c.label}"] == true) picked.add(c.label);
      }
      if (picked.isNotEmpty) map[g.title] = picked;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final extra = _extraTotal();
    final total = it.price + extra;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF1F6),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1.65,
                    child: buildAnyImageFlexible(
                      it.imagePath,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${widget.stall.name} - ${widget.stall.placeName}",
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          it.name,
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Base S\$${it.price.toStringAsFixed(2)}",
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Text(
                  it.desc,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(
                  it.optionGroups.isEmpty
                      ? "No customisations for this item."
                      : "Customisations",
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            if (it.optionGroups.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate((context, gi) {
                  final g = it.optionGroups[gi];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  g.title,
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                "Max ${g.maxSelect}",
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...g.choices.map((c) {
                            final key = "${g.title}|${c.label}";
                            final isSelected = _selected[key] == true;
                            final subtitle = c.extraPrice == 0
                                ? "Included"
                                : "+S\$${c.extraPrice.toStringAsFixed(2)}";

                            if (g.maxSelect <= 1) {
                              final selectedLabel = g.choices
                                  .map((choice) => choice.label)
                                  .firstWhere(
                                    (label) =>
                                        _selected["${g.title}|$label"] == true,
                                    orElse: () => "",
                                  );
                              return RadioListTile<String>(
                                value: c.label,
                                groupValue: selectedLabel.isEmpty
                                    ? null
                                    : selectedLabel,
                                onChanged: (_) => _toggleChoice(g, c, true),
                                title: Text(
                                  c.label,
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  subtitle,
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black45,
                                  ),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              );
                            }

                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (v) => _toggleChoice(g, c, v ?? false),
                              title: Text(
                                c.label,
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                subtitle,
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black45,
                                ),
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                }, childCount: it.optionGroups.length),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: it.soldOut
                ? null
                : () {
                    final id = DateTime.now().millisecondsSinceEpoch.toString();

                    final meta = <String, dynamic>{
                      'menuItemId': it.id,
                      'menuItemName': it.name,
                      'basePrice': it.price,
                      'extraPrice': extra,
                      'selectedOptions': _selectedOptionsPayload(),
                    };

                    widget.onAddToCart(
                      ConsumerOrder(
                        id: id,
                        stallName: widget.stall.name,
                        placeName: widget.stall.placeName,
                        itemCount: 1,
                        total: total,
                        status: OrderStatus.pendingPayment,
                        vendorUid: widget.stall.id,
                        meta: meta,
                      ),
                    );

                    Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              disabledBackgroundColor: Colors.black.withOpacity(0.12),
              disabledForegroundColor: Colors.black38,
            ),
            child: Text(
              it.soldOut
                  ? "Sold out"
                  : "Add to cart - S\$${total.toStringAsFixed(2)}",
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget buildAnyImageFlexible(
  String pathOrUrl, {
  double? w,
  double? h,
  BoxFit fit = BoxFit.cover,
}) {
  final s = pathOrUrl.trim();

  if (s.isEmpty) {
    return Container(
      width: w,
      height: h,
      color: Colors.black.withOpacity(0.06),
      child: const Icon(Icons.image_outlined, color: Colors.black45),
    );
  }

  bool looksLikeB64(String x) {
    if (x.length < 200) return false;
    final ok = RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
    return ok;
  }

  if (s.startsWith("b64:") || looksLikeB64(s)) {
    try {
      final b64 = s.startsWith("b64:") ? s.substring(4) : s;
      final bytes = base64Decode(b64);
      return Image.memory(bytes, width: w, height: h, fit: fit);
    } catch (_) {
      return Container(
        width: w,
        height: h,
        color: Colors.black.withOpacity(0.06),
        child: const Icon(Icons.broken_image_outlined, color: Colors.black45),
      );
    }
  }

  if (s.startsWith("http://") || s.startsWith("https://")) {
    return Image.network(
      s,
      width: w,
      height: h,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        width: w,
        height: h,
        color: Colors.black.withOpacity(0.06),
        child: const Icon(Icons.broken_image_outlined, color: Colors.black45),
      ),
    );
  }

  return Image.asset(
    s,
    width: w,
    height: h,
    fit: fit,
    errorBuilder: (_, __, ___) => Container(
      width: w,
      height: h,
      color: Colors.black.withOpacity(0.06),
      child: const Icon(Icons.broken_image_outlined, color: Colors.black45),
    ),
  );
}

class _PillFilter extends StatelessWidget {
  const _PillFilter({
    required this.icon,
    required this.label,
    required this.showClear,
    required this.onClear,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool showClear;
  final VoidCallback onClear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const border = Color(0xFFEAEAEA);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
            ),
            if (showClear) ...[
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16),
                ),
              ),
            ],
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

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String imagePath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 10),
              color: Colors.black.withOpacity(0.08),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              child: Image.asset(
                imagePath,
                width: 140,
                height: 76,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 140,
                  height: 76,
                  color: Colors.black.withOpacity(0.06),
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.black45,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                        fontSize: 11.5,
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

class _StallRowCard extends StatelessWidget {
  const _StallRowCard({required this.stall, required this.onTap});

  final StallModel stall;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = stall.vendorStatus.trim().toUpperCase();
    final pending = status.startsWith("PENDING");

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 10),
              color: Colors.black.withOpacity(0.08),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.storefront_rounded),
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
                          stall.name,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (pending)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            "PENDING",
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${stall.placeName} - ${stall.shortDesc}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        stall.rating.toStringAsFixed(1),
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}

class _CrowdCard extends StatelessWidget {
  const _CrowdCard({required this.stall, required this.crowd});
  final StallModel stall;
  final CrowdInfo crowd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.08),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: crowd.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                crowd.label,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            stall.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          Text(
            crowd.etaLabel,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class PlaceModel {
  const PlaceModel({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.imagePath,
  });
  final String id;
  final String name;
  final String subtitle;
  final String imagePath;
}

class PromoModel {
  const PromoModel({
    required this.title,
    required this.imagePath,
    required this.stallName,
    this.createdAtMs = 0,
  });
  final String title;
  final String imagePath;
  final String stallName;
  final int createdAtMs;
}

enum CrowdLevel { low, medium, crowded }

class CrowdInfo {
  const CrowdInfo({
    required this.level,
    required this.label,
    required this.etaLabel,
    required this.color,
  });
  final CrowdLevel level;
  final String label;
  final String etaLabel;
  final Color color;
}

class StallModel {
  const StallModel({
    required this.id,
    required this.name,
    this.stallNo,
    this.stallDocId,
    required this.placeId,
    required this.placeName,
    required this.shortDesc,
    required this.rating,
    required this.tags,
    required this.vendorStatus,
    required this.queueStatus,
    required this.isHalal,
    required this.paynowQrUrl,
    this.stallPhotoB64,
  });

  final String id;
  final String name;
  final String? stallNo;
  final String? stallDocId;
  final String placeId;
  final String placeName;
  final String shortDesc;
  final double rating;
  final Set<String> tags;

  final String vendorStatus;
  final String queueStatus;
  final bool isHalal;
  final String? paynowQrUrl;
  final String? stallPhotoB64;
}

enum OrderStatus { pendingPayment, placed, ready, pickedUp }

class ConsumerOrder {
  const ConsumerOrder({
    required this.id,
    required this.stallName,
    required this.placeName,
    required this.itemCount,
    required this.total,
    required this.status,
    this.vendorUid,
    this.meta,
  });

  final String id;
  final String stallName;
  final String placeName;
  final int itemCount;
  final double total;
  final OrderStatus status;
  final String? vendorUid;

  final Map<String, dynamic>? meta;

  ConsumerOrder copyWith({OrderStatus? status}) {
    return ConsumerOrder(
      id: id,
      stallName: stallName,
      placeName: placeName,
      itemCount: itemCount,
      total: total,
      status: status ?? this.status,
      vendorUid: vendorUid,
      meta: meta,
    );
  }
}

class ConsumerReview {
  const ConsumerReview({
    required this.stallName,
    required this.user,
    required this.rating,
    required this.comment,
    required this.daysAgo,
  });
  final String stallName;
  final String user;
  final int rating;
  final String comment;
  final int daysAgo;
}

class _RecentReviewItem {
  const _RecentReviewItem({
    required this.stallName,
    required this.placeName,
    required this.userName,
    required this.comment,
    required this.rating,
    required this.createdAt,
  });

  final String stallName;
  final String placeName;
  final String userName;
  final String comment;
  final int rating;
  final Timestamp? createdAt;
}

class MenuItemModel {
  const MenuItemModel({
    required this.id,
    required this.name,
    required this.desc,
    required this.price,
    required this.imagePath,
    this.optionGroups = const [],
    this.soldOut = false,
  });

  final String id;
  final String name;
  final String desc;
  final double price;
  final String imagePath;
  final List<OptionGroup> optionGroups;
  final bool soldOut;
}

class OptionGroup {
  const OptionGroup({
    required this.title,
    required this.maxSelect,
    required this.choices,
  });
  final String title;
  final int maxSelect;
  final List<OptionChoice> choices;
}

class OptionChoice {
  const OptionChoice({required this.label, required this.extraPrice});
  final String label;
  final double extraPrice;
}




