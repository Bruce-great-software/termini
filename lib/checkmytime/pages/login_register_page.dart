import 'dart:io';

import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/home_page.dart';
import 'package:termini/checkmytime/pages/sms_verification_page.dart';
import 'package:termini/checkmytime/services/pnv_auth_service.dart';
import 'package:termini/checkmytime/services/pnv_service.dart';
import 'package:termini/checkmytime/widgets/checkmytime_ui.dart';

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
      _showMessage('Bitte gib eine gueltige Handynummer ein.');
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
                MaterialPageRoute(builder: (_) => const CheckMyTimeHomePage()),
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
          builder:
              (_) => SmsVerificationPage(
                phoneNumberE164: manualPhone,
                isLoginMode: isLoginMode,
              ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Fehler beim Starten der Anmeldung. ($e)');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(isLoginMode ? 'Login' : 'Registrierung')),
      body: CheckMyTimeGradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              CheckMyTimeHeroCard(
                eyebrow: isLoginMode ? 'Willkommen zurueck' : 'Neues Konto',
                title:
                    isLoginMode
                        ? 'Schnell wieder in CheckMyTime'
                        : 'In wenigen Sekunden startklar',
                description:
                    isLoginMode
                        ? 'Melde dich mit deiner Handynummer an und steige direkt in deine Kontakte, Termine und Events ein.'
                        : 'Registriere dich mit deiner Handynummer und richte anschliessend dein Profil ein.',
                trailing: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isLoginMode
                        ? Icons.login_rounded
                        : Icons.person_add_alt_1_rounded,
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
                      'Handynummer',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Wir nutzen deine Mobilnummer fuer Login, Registrierung und spaeter fuer SMS-Bestaetigungen.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 88,
                          height: 58,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: colorScheme.primary.withValues(
                                alpha: 0.14,
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'DE',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '+49',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
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
                              hintText:
                                  isLoginMode
                                      ? 'Handynummer fuer Login'
                                      : 'Handynummer fuer Registrierung',
                              prefixIcon: const Icon(
                                Icons.phone_iphone_rounded,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isLoading ? null : _handleAuth,
                        icon:
                            isLoading
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : Icon(
                                  isLoginMode
                                      ? Icons.arrow_forward_rounded
                                      : Icons.verified_user_outlined,
                                ),
                        label: Text(
                          isLoading
                              ? 'Wird vorbereitet...'
                              : (isLoginMode
                                  ? 'Mit SMS fortfahren'
                                  : 'Konto erstellen'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CheckMyTimeSectionCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      isLoginMode ? 'Noch kein Konto?' : 'Schon registriert?',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isLoginMode
                          ? 'Du kannst mit derselben Nummer direkt loslegen und dein Profil spaeter vervollstaendigen.'
                          : 'Wechsle wieder in den Login, wenn deine Nummer bereits registriert ist.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        setState(() => isLoginMode = !isLoginMode);
                      },
                      child: Text(
                        isLoginMode
                            ? 'Jetzt registrieren'
                            : 'Zum Login wechseln',
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
