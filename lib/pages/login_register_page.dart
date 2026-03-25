import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'alle_dienstleister_page.dart';
import 'dienstleister_main_page.dart';
import 'admin_page.dart';
import 'sms_verification_page.dart';

class LoginRegisterPage extends StatefulWidget {
  const LoginRegisterPage({super.key});

  @override
  State<LoginRegisterPage> createState() => _LoginRegisterPageState();
}

class _LoginRegisterPageState extends State<LoginRegisterPage> {
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoginMode = true;
  bool isLoading = false;

  Future<void> _handleAuth() async {
    if (!isLoginMode && _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gib eine Handynummer ein.')),
      );
      return;
    }

    if (!isLoginMode && _emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gib eine E-Mail ein.')),
      );
      return;
    }

    if (!isLoginMode && _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gib ein Passwort ein.')),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      UserCredential credential;
      final auth = FirebaseAuth.instance;

      if (isLoginMode) {
        credential = await auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await _startPhoneVerification();
        return;
      }

      // Rolle prüfen
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .get();

      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Benutzer existiert nicht in der Nutzersammlung.')),
        );
        setState(() => isLoading = false);
        return;
      }

      final data = doc.data();
      final rolle = data?['rolle']?.toString().toLowerCase();

      if (rolle == 'kunde') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()),
        );
      } else if (rolle == 'dienstleister') {
        final branche = data?['branche'];
        final dienstleisterId = data?['dienstleisterId'];

        if (branche != null && dienstleisterId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DienstleisterMainPage(
                branche: branche,
                dienstleisterId: dienstleisterId,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Daten für Dienstleister unvollständig.')),
          );
        }
      } else if (rolle == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMainPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unbekannte oder fehlende Rolle im Nutzerprofil.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: ${e.toString()}')),
      );
    }
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _startPhoneVerification() async {
    final formattedPhone = _formatGermanPhoneNumber(_phoneController.text);
    if (formattedPhone == null) {
      if (mounted) {
        setState(() => isLoading = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gib eine gültige Handynummer ein.')),
      );
      return;
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: formattedPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS-Code wurde automatisch erkannt. Bitte bestätigen.'),
          ),
        );
      },
      verificationFailed: (FirebaseAuthException error) {
        if (!mounted) {
          return;
        }
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message ?? 'SMS konnte nicht gesendet werden.',
            ),
          ),
        );
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) {
          return;
        }
        setState(() => isLoading = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SmsVerificationPage(
              phoneNumberE164: formattedPhone,
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
              verificationId: verificationId,
              resendToken: resendToken,
            ),
          ),
        );
      },
      codeAutoRetrievalTimeout: (_) {
        if (!mounted) {
          return;
        }
        setState(() => isLoading = false);
      },
    );
  }

  String? _formatGermanPhoneNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith('+')) {
      final digits = normalized.substring(1);
      if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) {
        return null;
      }
      return '+$digits';
    }

    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      return null;
    }

    if (normalized.startsWith('00')) {
      final digits = normalized.substring(2);
      return digits.isEmpty ? null : '+$digits';
    }

    if (normalized.startsWith('49')) {
      return '+$normalized';
    }

    final local = normalized.replaceFirst(RegExp(r'^0+'), '');
    if (local.isEmpty) {
      return null;
    }

    return '+49$local';
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLoginMode ? 'Login' : 'Registrierung')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isLoginMode) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Handynummer *',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF344054),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    height: 56,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD0D5DD)),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🇩🇪', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 8),
                        Text(
                          '+49',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF101828),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: 'Handynummer',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'E-Mail'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Passwort'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleAuth,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: isLoginMode
                            ? null
                            : const Color(0xFF1F1F1F),
                        foregroundColor: isLoginMode ? null : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: isLoginMode ? null : 0,
                      ),
                      child: Text(
                        isLoginMode ? 'Login' : 'Ein Konto erstellen',
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() => isLoginMode = !isLoginMode);
              },
              child: Text(isLoginMode
                  ? 'Noch kein Konto? Jetzt registrieren'
                  : 'Bereits registriert? Jetzt einloggen'),
            ),
          ],
        ),
      ),
    );
  }
}
