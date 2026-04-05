import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_page.dart';
import 'alle_dienstleister_page.dart';
import 'dienstleister_main_page.dart';

class SmsVerificationPage extends StatefulWidget {
  const SmsVerificationPage({
    super.key,
    required this.phoneNumberE164,
    required this.verificationId,
    required this.isLoginMode,
    this.resendToken,
  });

  final String phoneNumberE164;
  final String verificationId;
  final bool isLoginMode;
  final int? resendToken;

  @override
  State<SmsVerificationPage> createState() => _SmsVerificationPageState();
}

class _SmsVerificationPageState extends State<SmsVerificationPage> {
  final _codeController = TextEditingController();
  late String _verificationId;
  int? _resendToken;
  bool _isSaving = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCodeAndContinue() async {
    final smsCode = _codeController.text.trim();
    if (smsCode.isEmpty) {
      _showSnackBar('Bitte gib den Bestätigungscode ein.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: smsCode,
      );

      await _completePhoneAuth(credential);
    } on FirebaseAuthException catch (error) {
      _showSnackBar(error.message ?? 'Code konnte nicht verifiziert werden.');
    } catch (_) {
      _showSnackBar('Code konnte nicht verifiziert werden.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isResending = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumberE164,
        forceResendingToken: _resendToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) {},
        verificationFailed: (FirebaseAuthException error) {
          _showSnackBar(error.message ?? 'Neuer Code konnte nicht gesendet werden.');
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) {
            return;
          }
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          _showSnackBar('Neuer Code wurde gesendet.');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) {
            return;
          }
          setState(() {
            _verificationId = verificationId;
          });
        },
      );
    } catch (_) {
      _showSnackBar('Neuer Code konnte nicht gesendet werden.');
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _completePhoneAuth(PhoneAuthCredential phoneCredential) async {
    final auth = FirebaseAuth.instance;

    try {
      final phoneUserCredential = await auth.signInWithCredential(phoneCredential);
      final currentUser = phoneUserCredential.user;

      if (currentUser == null) {
        _showSnackBar('Anmeldung konnte nicht abgeschlossen werden.');
        return;
      }

      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);
      final userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        await userDocRef.set({
          'displayName': '',
          'phoneNumber': widget.phoneNumberE164,
          'authProvider': 'phone',
          'rolle': 'kunde',
          'isActive': true,
          'profileCompleted': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      final freshUserDoc = await userDocRef.get();
      final data = freshUserDoc.data();
      final rolle = data?['rolle']?.toString().toLowerCase();

      if (!mounted) {
        return;
      }

      if (rolle == 'kunde') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AlleDienstleisterPage()),
          (route) => false,
        );
      } else if (rolle == 'dienstleister') {
        final branche = data?['branche'];
        final dienstleisterId = data?['dienstleisterId'];

        if (branche != null && dienstleisterId != null) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => DienstleisterMainPage(
                branche: branche,
                dienstleisterId: dienstleisterId,
              ),
            ),
            (route) => false,
          );
        } else {
          _showSnackBar('Daten für Dienstleister unvollständig.');
        }
      } else if (rolle == 'admin') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AdminMainPage()),
          (route) => false,
        );
      } else {
        _showSnackBar('Unbekannte oder fehlende Rolle im Nutzerprofil.');
      }
    } on FirebaseAuthException catch (error) {
      if (error.code == 'invalid-verification-code') {
        _showSnackBar('Der eingegebene Code ist ungültig.');
      } else if (error.code == 'session-expired') {
        _showSnackBar('Der Code ist abgelaufen. Bitte fordere einen neuen an.');
      } else {
        _showSnackBar(
          error.message ?? 'Anmeldung konnte nicht abgeschlossen werden.',
        );
      }
    } catch (_) {
      _showSnackBar('Anmeldung konnte nicht abgeschlossen werden.');
    }
  }

  Future<void> _logoutAndCancel() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isLoginMode ? 'Login per SMS' : 'Registrierung per SMS',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bitte geben Sie den SMS-Bestätigungscode ein, der an folgende Nummer '
              'verschickt wurde: ${widget.phoneNumberE164}',
              style: const TextStyle(
                fontSize: 20,
                height: 1.35,
                color: Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Bestätigungscode - Beispiel: 123456',
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sie haben keine SMS erhalten?',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF475467),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _isSaving || _isResending ? null : _resendCode,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.zero,
                foregroundColor: const Color(0xFF101828),
              ),
              child: Text(
                _isResending ? 'Code wird angefordert...' : 'Einen neuen Code anfordern',
                style: const TextStyle(
                  fontSize: 28,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _verifyCodeAndContinue,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: const Color(0xFF1F1F1F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Speichern',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isSaving ? null : _logoutAndCancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: const BorderSide(color: Color(0xFF98A2B3)),
                ),
                child: const Text(
                  'Ausloggen',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
