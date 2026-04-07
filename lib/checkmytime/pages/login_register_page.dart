import 'package:flutter/material.dart';
import 'sms_verification_page.dart';

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
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gib eine Handynummer ein.')),
      );
      return;
    }

    final formattedPhone = _formatGermanPhoneNumber(_phoneController.text);
    if (formattedPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gib eine gültige Handynummer ein.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmsVerificationPage(
          phoneNumberE164: formattedPhone,
          isLoginMode: isLoginMode,
        ),
      ),
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
                  isLoginMode
                      ? 'Per SMS einloggen'
                      : 'Ein Konto erstellen',
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