import 'dart:io';

import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/home_page.dart';
import 'package:termini/checkmytime/pages/sms_verification_page.dart';
import 'package:termini/checkmytime/services/pnv_auth_service.dart';
import 'package:termini/checkmytime/services/pnv_service.dart';

class LoginRegisterPage extends StatefulWidget {
  const LoginRegisterPage({super.key});

  @override
  State<LoginRegisterPage> createState() => _LoginRegisterPageState();
}

class _LoginRegisterPageState extends State<LoginRegisterPage> {
  final _phoneController = TextEditingController();

  bool isLoginMode = true;
  bool isLoading = false;

  Future<void> _handleAuth() async {
    final manualPhone = _formatGermanPhoneNumber(_phoneController.text);

    if (_phoneController.text.trim().isEmpty) {
      _showMessage('Bitte gib eine Handynummer ein.');
      return;
    }

    if (manualPhone == null) {
      _showMessage('Bitte gib eine gültige Handynummer ein.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      if (Platform.isAndroid) {
        final supported = await PnvService.isSupported();

        if (supported) {
          try {
            final pnvResult = await PnvService.getVerifiedPhoneNumber();

            if (!mounted) return;

            if (pnvResult != null) {
              await PnvAuthService.signInWithPnv(
                phoneNumber: pnvResult.phoneNumber,
                token: pnvResult.token,
              );

              if (!mounted) return;

              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const CheckMyTimeHomePage(),
                ),
                    (route) => false,
              );

              return;
            }
          } catch (e) {
            if (!mounted) return;
            _showMessage(
              'PNV konnte nicht abgeschlossen werden. Wir nutzen SMS. ($e)',
            );
          }
        }
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SmsVerificationPage(
            phoneNumberE164: manualPhone,
            isLoginMode: isLoginMode,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Fehler beim Starten der Anmeldung. ($e)');
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isLoginMode ? 'Login' : 'Registrierung'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
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
                    decoration: InputDecoration(
                      hintText: isLoginMode
                          ? 'Handynummer für Login'
                          : 'Handynummer für Registrierung',
                    ),
                  ),
                ),
              ],
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
                  backgroundColor:
                  isLoginMode ? null : const Color(0xFF1F1F1F),
                  foregroundColor: isLoginMode ? null : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: isLoginMode ? null : 0,
                ),
                child: Text(
                  isLoginMode ? 'Einloggen' : 'Ein Konto erstellen',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() => isLoginMode = !isLoginMode);
              },
              child: Text(
                isLoginMode
                    ? 'Noch kein Konto? Jetzt registrieren'
                    : 'Bereits registriert? Jetzt einloggen',
              ),
            ),
          ],
        ),
      ),
    );
  }
}