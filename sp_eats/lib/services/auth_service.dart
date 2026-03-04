import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';

class PendingVendorApprovalException implements Exception {
  final String status;

  PendingVendorApprovalException(this.status);

  @override
  String toString() =>
      'Vendor account is not approved yet (current status: $status).';
}

class UserProfileException implements Exception {
  final String message;

  UserProfileException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<UserCredential> registerConsumer({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw UserProfileException('User creation failed.');
    }

    try {
      await _users.doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? email,
        'role': 'consumer',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      await user.delete();
      rethrow;
    }

    await _auth.signOut();

    return credential;
  }

  Future<UserCredential> registerVendor({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw UserProfileException('User creation failed.');
    }

    try {
      await _users.doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? email,
        'role': 'vendor',
        'vendorStatus': 'PENDING',
        'vendorDetailsSubmitted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      await user.delete();
      rethrow;
    }

    return credential;
  }

  Future<UserCredential> loginConsumer({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    await _validateRole(credential.user, expectedRole: 'consumer');
    await _users.doc(credential.user!.uid).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return credential;
  }

  Future<void> logout() => _auth.signOut();

  Future<Map<String, dynamic>?> getMyProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await _users.doc(uid).get();
    return snap.data();
  }

  Future<void> submitVendorDetailsWithImages({
    required String stallNo,
    required String stallName,
    required String stallLocation,
    required bool isHalal,
    required List<int>? stallPhotoBytes,
    required List<int>? verificationDocBytes,
    required List<int>? halalCertBytes,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw UserProfileException('You must be logged in as a vendor.');
    }

    final profile = await _validateRole(user, expectedRole: 'vendor');
    final foodCourtId = _toFoodCourtId(stallLocation);
    if (foodCourtId == null) {
      throw UserProfileException('Invalid food court location selected.');
    }

    if (stallPhotoBytes == null || verificationDocBytes == null) {
      throw UserProfileException('Required files are missing.');
    }
    if (isHalal && halalCertBytes == null) {
      throw UserProfileException('Halal certificate is required.');
    }

    final now = FieldValue.serverTimestamp();
    final vendorDocRef = _firestore
        .collection('foodcourts')
        .doc(foodCourtId)
        .collection('stalls')
        .doc(user.uid);

    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(vendorDocRef);
      Object createdAt = now;
      if (existing.exists) {
        final existingData = existing.data();
        final existingCreatedAt = existingData?['createdAt'];
        if (existingCreatedAt != null) {
          createdAt = existingCreatedAt;
        }
      }

      tx.set(vendorDocRef, {
        'uid': user.uid,
        'email': profile['email'] ?? user.email,
        'stallName': stallName,
        'stallNumber': stallNo,
        'location': stallLocation,
        'foodCourtId': foodCourtId,
        'halalStatus': isHalal,
        'halalCertB64': isHalal ? base64Encode(halalCertBytes!) : '',
        'stallPhotoB64': base64Encode(stallPhotoBytes),
        'verificationDocB64': base64Encode(verificationDocBytes),
        'createdAt': createdAt,
        'updatedAt': now,
      }, SetOptions(merge: true));

      tx.set(_users.doc(user.uid), {
        'vendorStatus': 'PENDING',
        'vendorDetailsSubmitted': true,
        'stallName': stallName,
        'stallNo': stallNo,
        'stallLocation': stallLocation,
        'foodCourtId': foodCourtId,
        'isHalal': isHalal,
        'updatedAt': now,
      }, SetOptions(merge: true));
    });
  }

  Future<UserCredential> loginVendor({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final data = await _validateRole(credential.user, expectedRole: 'vendor');
    final status = ((data['vendorStatus'] ?? data['vendorstatus']) as String? ??
            'PENDING')
        .toUpperCase();

    if (status != 'APPROVED') {
      await _auth.signOut();
      throw PendingVendorApprovalException(status);
    }

    await _users.doc(credential.user!.uid).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  Future<Map<String, dynamic>> _validateRole(
    User? user, {
    required String expectedRole,
  }) async {
    if (user == null) {
      throw UserProfileException('No signed-in user found.');
    }

    final snapshot = await _users.doc(user.uid).get();
    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      await _auth.signOut();
      throw UserProfileException('User profile not found in Firestore.');
    }

    final role = (data['role'] as String? ?? '').toLowerCase();
    if (role != expectedRole) {
      await _auth.signOut();
      throw UserProfileException('This account is not a $expectedRole account.');
    }

    return data;
  }

  String? _toFoodCourtId(String location) {
    final normalized = location.trim().toLowerCase();
    switch (normalized) {
      case 'food court 1':
        return 'fc1';
      case 'food court 2':
        return 'fc2';
      case 'food court 3':
        return 'fc3';
      case 'food court 4':
        return 'fc4';
      case 'food court 5':
        return 'fc5';
      case 'food court 6':
        return 'fc6';
      case 'moberly cafe':
        return 'moberly_cafe';
      case 'old chang kee':
        return 'old_chang_kee';
      default:
        return null;
    }
  }
}
