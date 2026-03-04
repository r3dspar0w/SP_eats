import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../css.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AppBackground(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Text(
                    "Welcome to SP Eats",
                    style: GoogleFonts.manrope(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: const Color.fromARGB(255, 44, 3, 38),
                    ),
                  ),
                  const SizedBox(height: 15),

                  RoleCard(
                    image: "assets/img/vendor.png",
                    title: "Vendor",
                    onTap: () => Navigator.pushNamed(context, '/vendor_register'),
                  ),

                  const SizedBox(height: 20),

                  RoleCard(
                    image: "assets/img/consumer.png",
                    title: "Student / Staff",
                    onTap: () => Navigator.pushNamed(context, '/consumer_register'),
                  ),

                  const SizedBox(height: 10),
                  Text(
                    "Select your role to continue",
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: const Color.fromARGB(179, 91, 86, 86),
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

class RoleCard extends StatelessWidget {
  final String image;
  final String title;
  final VoidCallback onTap;

  const RoleCard({
    super.key,
    required this.image,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(22),
        color: Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 15),
            child: Column(
              children: [
                Image.asset(image, height: 200),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
