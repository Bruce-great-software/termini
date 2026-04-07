import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PnvAuthService {
  static final FirebaseFunctions _functions =
  FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<UserCredential> signInWithPnv({
    required String phoneNumber,
    required String token,
  }) async {
    final callable = _functions.httpsCallable('exchangePnvToken');

    final result = await callable.call({
      'phoneNumber': phoneNumber,
      'token': token,
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    final customToken = (data['customToken'] ?? '').toString();

    if (customToken.isEmpty) {
      throw Exception('Kein Custom Token vom Backend erhalten.');
    }

    final credential =
    await FirebaseAuth.instance.signInWithCustomToken(customToken);

    return credential;
  }
}