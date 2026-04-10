import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/create_event_page.dart';

/// Übergangsseite: alte Termin-Erstellung leitet auf die gemeinsame
/// Event-Erstellung um.
class CreateAppointmentPage extends StatelessWidget {
  final String contactId;
  final String contactName;

  const CreateAppointmentPage({
    super.key,
    required this.contactId,
    required this.contactName,
  });

  @override
  Widget build(BuildContext context) {
    return CreateEventPage(
      initialContactId: contactId,
      initialContactName: contactName,
    );
  }
}
