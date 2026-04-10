import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/events_page.dart';

/// Übergangsseite: leitet alte Appointment-Navigation auf die gemeinsame
/// Event-Übersicht um.
class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EventsPage();
  }
}
