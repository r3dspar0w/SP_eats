import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'pages/consumer_home_page.dart';
import 'pages/consumer_login_page.dart';
import 'pages/consumer_register_page.dart';
import 'pages/vendor_login_page.dart';
import 'pages/vendor_home_page.dart';
import 'pages/vendor_pending_approval_page.dart';
import 'pages/vendor_register_page.dart';
import 'pages/vendor_verify_page.dart';
import 'pages/welcome_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  GoogleFonts.config.allowRuntimeFetching = true;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      routes: {
        '/consumer_home': (_) => const ConsumerHomePage(),
        '/consumer_register': (_) => const ConsumerRegisterPage(),
        '/consumer_login': (_) => const ConsumerLoginPage(),
        '/vendor_register': (_) => const VendorRegisterPage(),
        '/vendor_login': (_) => const VendorLoginPage(),
        '/vendor_home': (_) => const VendorHomePage(),
        '/vendor_verify': (_) => const VendorVerifyPage(),
        '/vendor_pending': (_) => const VendorPendingApprovalPage(),
      },
      home: const WelcomePage(),
    );
  }
}
