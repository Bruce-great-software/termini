import 'package:flutter/services.dart';

class PnvResult {
  final String phoneNumber;
  final String token;

  const PnvResult({
    required this.phoneNumber,
    required this.token,
  });
}

class PnvService {
  static const MethodChannel _channel = MethodChannel('checkmytime/pnv');

  static Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<PnvResult?> getVerifiedPhoneNumber() async {
    try {
      final result =
      await _channel.invokeMapMethod<String, dynamic>('getVerifiedPhoneNumber');

      if (result == null) return null;

      final phoneNumber = (result['phoneNumber'] ?? '').toString();
      final token = (result['token'] ?? '').toString();

      if (phoneNumber.isEmpty || token.isEmpty) {
        return null;
      }

      return PnvResult(
        phoneNumber: phoneNumber,
        token: token,
      );
    } on PlatformException {
      return null;
    }
  }
}