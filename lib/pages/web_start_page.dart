import 'package:flutter/material.dart';
import 'alle_dienstleister_page.dart';
import 'login_register_page.dart';

class WebStartPage extends StatelessWidget {
  const WebStartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 760,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/termini.png',
                    fit: BoxFit.cover,
                  ),

                  Container(
                    color: Colors.black.withOpacity(0.28),
                  ),

                  Column(
                    children: [
                      Container(
                        height: 76,
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        color: Colors.white,
                        child: Row(
                          children: [
                            const Text(
                              'TERMINI',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 4,
                                color: Colors.black,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black87,
                              ),
                              child: const Text(
                                'Friseur',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black87,
                              ),
                              child: const Text(
                                'Barbershop',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black87,
                              ),
                              child: const Text(
                                'Kosmetik',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 28),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF111111),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginRegisterPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.person_outline, size: 20),
                              label: const Text(
                                'Mein Konto',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Buchen Sie Ihren Termin',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 54,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'Schnell • Einfach • Online',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 38),

                                Container(
                                  constraints:
                                  const BoxConstraints(maxWidth: 920),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.18),
                                        blurRadius: 24,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 6,
                                          ),
                                          decoration: const BoxDecoration(
                                            border: Border(
                                              right: BorderSide(
                                                color: Color(0xFFE6E6E6),
                                              ),
                                            ),
                                          ),
                                          child: const TextField(
                                            decoration: InputDecoration(
                                              border: InputBorder.none,
                                              isDense: true,
                                              hintText:
                                              'Salonname, Dienstleistung...',
                                              labelText: 'Was suchen Sie?',
                                              labelStyle: TextStyle(
                                                color: Color(0xFF8A8A8A),
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 6,
                                          ),
                                          child: const TextField(
                                            decoration: InputDecoration(
                                              border: InputBorder.none,
                                              isDense: true,
                                              hintText: 'Adresse, Stadt...',
                                              labelText: 'Wo',
                                              labelStyle: TextStyle(
                                                color: Color(0xFF8A8A8A),
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        height: 56,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                            const Color(0xFF111111),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 28,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.circular(12),
                                            ),
                                          ),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                const AlleDienstleisterPage(),
                                              ),
                                            );
                                          },
                                          child: const Text(
                                            'Suchen',
                                            style: TextStyle(

                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
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
    );
  }
}