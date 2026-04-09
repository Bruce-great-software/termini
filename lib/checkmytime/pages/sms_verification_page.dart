import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/home_page.dart';
import 'package:termini/checkmytime/widgets/checkmytime_ui.dart';

class SmsVerificationPage extends StatefulWidget {
  const SmsVerificationPage({
    super.key,
    required this.phoneNumberE164,
    required this.isLoginMode,
  });

  final String phoneNumberE164;
  final bool isLoginMode;

  @override
  State<SmsVerificationPage> createState() => _SmsVerificationPageState();
}

class _SmsVerificationPageState extends State<SmsVerificationPage> {
  final _codeController = TextEditingController();
  String? _verificationId;
  int? _resendToken;
  bool _isSaving = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _sendInitialCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCodeAndContinue() async {
    final smsCode = _codeController.text.trim();
    if (smsCode.isEmpty) {
      _showSnackBar('Bitte gib den Bestaetigungscode ein.');
      return;
    }
    if (_verificationId == null || _verificationId!.isEmpty) {
      _showSnackBar('Der SMS-Code wird noch angefordert. Bitte kurz warten.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
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
          _showSnackBar(
            error.message ?? 'Neuer Code konnte nicht gesendet werden.',
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          _showSnackBar('Neuer Code wurde gesendet.');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
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

  Future<void> _sendInitialCode() async {
    setState(() => _isResending = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumberE164,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) {},
        verificationFailed: (FirebaseAuthException error) {
          _showSnackBar(error.message ?? 'SMS konnte nicht gesendet werden.');
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
          });
        },
      );
    } catch (_) {
      _showSnackBar('SMS konnte nicht gesendet werden.');
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _completePhoneAuth(PhoneAuthCredential phoneCredential) async {
    final auth = FirebaseAuth.instance;

    try {
      final phoneUserCredential = await auth.signInWithCredential(
        phoneCredential,
      );
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

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const CheckMyTimeHomePage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'invalid-verification-code') {
        _showSnackBar('Der eingegebene Code ist ungueltig.');
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
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: CheckMyTimeGradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              CheckMyTimeHeroCard(
                eyebrow: widget.isLoginMode ? 'SMS Login' : 'SMS Registrierung',
                title: 'Code bestaetigen',
                description:
                    'Wir haben einen SMS-Code an ${widget.phoneNumberE164} geschickt. Gib ihn hier ein, um fortzufahren.',
                trailing: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.sms_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CheckMyTimeSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bestaetigungscode',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Der Code besteht in der Regel aus sechs Ziffern. Falls nichts ankommt, kannst du unten einen neuen Code anfordern.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Bestaetigungscode, z. B. 123456',
                        prefixIcon: Icon(Icons.password_rounded),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _verifyCodeAndContinue,
                        icon:
                            _isSaving
                                ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _isSaving ? 'Wird geprueft...' : 'Code bestaetigen',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CheckMyTimeSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kein Code angekommen?',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Fordere eine neue SMS an oder brich den Vorgang ab, wenn du eine andere Nummer verwenden willst.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _isSaving || _isResending ? null : _resendCode,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        _isResending
                            ? 'Code wird angefordert...'
                            : 'Neuen Code anfordern',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _logoutAndCancel,
                        icon: const Icon(Icons.logout),
                        label: const Text('Abbrechen und ausloggen'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
