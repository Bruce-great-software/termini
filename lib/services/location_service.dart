import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Position?> initLocation({
    required BuildContext context,
    required VoidCallback onExitApp,
    required VoidCallback onOpenAppSettings,
  }) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      await _showLocationDisabledDialog(context, onExitApp);
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      await _showPermissionDeniedForeverDialog(context, onOpenAppSettings, onExitApp);
      return null;
    }

    if (permission == LocationPermission.denied) {
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }

  static Future<void> _showLocationDisabledDialog(
      BuildContext context,
      VoidCallback onExitApp,
      ) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Standort deaktiviert'),
        content: const Text('Bitte aktiviere den Standortdienst in den Systemeinstellungen, um Dienstleister in deiner Nähe zu sehen.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: const Text('Standort aktivieren'),
          ),
          TextButton(
            onPressed: onExitApp,
            child: const Text('App schließen'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showPermissionDeniedForeverDialog(
      BuildContext context,
      VoidCallback onOpenAppSettings,
      VoidCallback onExitApp,
      ) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Standortberechtigung verweigert'),
        content: const Text('Du hast den Standort dauerhaft blockiert. Bitte oeffne die App-Einstellungen, um die Berechtigung manuell zu erteilen.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onOpenAppSettings();
            },
            child: const Text('Einstellungen oeffnen'),
          ),
          TextButton(
            onPressed: onExitApp,
            child: const Text('App schließen'),
          ),
        ],
      ),
    );
  }
}
