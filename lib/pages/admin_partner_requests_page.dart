import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AdminPartnerRequestsPage extends StatelessWidget {
  const AdminPartnerRequestsPage({super.key});

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '—';
    final date = timestamp.toDate();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.$year • $hour:$minute';
  }

  Future<void> _rejectRequest(
      BuildContext context,
      DocumentSnapshot doc,
      ) async {
    try {
      await doc.reference.update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anfrage wurde abgelehnt')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Ablehnen: $e')),
      );
    }
  }

  Future<void> _openReviewDialog(
      BuildContext context,
      DocumentSnapshot doc,
      ) async {
    final data = doc.data() as Map<String, dynamic>;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PartnerRequestReviewDialog(
        requestId: doc.id,
        requestData: data,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 14,
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value.isEmpty ? '—' : value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 1100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Offene Partner-Anfragen',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hier erscheinen alle Dienstleister-Anträge mit Status „pending“.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('partner_requests')
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Fehler beim Laden der Partner-Anfragen: ${snapshot.error}',
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];

                      docs.sort((a, b) {
                        final aTs =
                        (a.data() as Map<String, dynamic>)['createdAt']
                        as Timestamp?;
                        final bTs =
                        (b.data() as Map<String, dynamic>)['createdAt']
                        as Timestamp?;
                        final aMs = aTs?.millisecondsSinceEpoch ?? 0;
                        final bMs = bTs?.millisecondsSinceEpoch ?? 0;
                        return bMs.compareTo(aMs);
                      });

                      if (docs.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Center(
                            child: Text(
                              'Aktuell gibt es keine offenen Partner-Anfragen.',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;

                          final geschaeftsname =
                          (data['geschaeftsname'] ?? '').toString();
                          final branche = (data['branche'] ?? '').toString();
                          final vorname = (data['vorname'] ?? '').toString();
                          final nachname = (data['nachname'] ?? '').toString();
                          final email = (data['email'] ?? '').toString();
                          final telefon = (data['telefon'] ?? '').toString();
                          final strassenname =
                          (data['strassenname'] ?? '').toString();
                          final hausnummer =
                          (data['hausnummer'] ?? '').toString();
                          final plz = (data['plz'] ?? '').toString();
                          final stadt = (data['stadt'] ?? '').toString();
                          final createdAt = data['createdAt'] as Timestamp?;

                          final adresse = [
                            strassenname,
                            hausnummer,
                          ].where((e) => e.trim().isNotEmpty).join(' ').trim();

                          final ortPlz = [
                            plz,
                            stadt,
                          ].where((e) => e.trim().isNotEmpty).join(' ').trim();

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              geschaeftsname.isEmpty
                                                  ? 'Unbenanntes Geschäft'
                                                  : geschaeftsname,
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange
                                                        .withOpacity(0.10),
                                                    borderRadius:
                                                    BorderRadius.circular(
                                                        999),
                                                  ),
                                                  child: Text(
                                                    branche.isEmpty
                                                        ? 'Ohne Branche'
                                                        : branche,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                      FontWeight.w600,
                                                      color: Colors.deepOrange,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue
                                                        .withOpacity(0.10),
                                                    borderRadius:
                                                    BorderRadius.circular(
                                                        999),
                                                  ),
                                                  child: const Text(
                                                    'pending',
                                                    style: TextStyle(
                                                      fontWeight:
                                                      FontWeight.w600,
                                                      color: Colors.blue,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        _formatTimestamp(createdAt),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  _buildInfoRow(
                                    'Ansprechpartner',
                                    '$vorname $nachname'.trim(),
                                  ),
                                  _buildInfoRow('E-Mail', email),
                                  _buildInfoRow('Telefon', telefon),
                                  _buildInfoRow('Adresse', adresse),
                                  _buildInfoRow('Ort / PLZ', ortPlz),
                                  _buildInfoRow('UID', doc.id),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _openReviewDialog(context, doc),
                                        icon: const Icon(Icons.search),
                                        label: const Text('Prüfen'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _rejectRequest(context, doc),
                                        icon: const Icon(Icons.close),
                                        label: const Text('Ablehnen'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PartnerRequestReviewDialog extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> requestData;

  const PartnerRequestReviewDialog({
    super.key,
    required this.requestId,
    required this.requestData,
  });

  @override
  State<PartnerRequestReviewDialog> createState() =>
      _PartnerRequestReviewDialogState();
}

class _PartnerRequestReviewDialogState
    extends State<PartnerRequestReviewDialog> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _suchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _adresseController = TextEditingController();
  final TextEditingController _ortController = TextEditingController();
  final TextEditingController _plzController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  final String apiKey = 'AIzaSyAAydUpc7KvbbEGeUDsw4DF8w2BkpL_Rq0';

  List<Map<String, dynamic>> _suggestions = [];
  bool _loadingSuggestions = false;
  bool _isApproving = false;

  String? _branche;
  List<String> _branchenListe = [];

  @override
  void initState() {
    super.initState();
    _prefillFromRequest();
    _loadBranchen();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveInitialAddress();
    });
  }

  @override
  void dispose() {
    _suchController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _adresseController.dispose();
    _ortController.dispose();
    _plzController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _prefillFromRequest() {
    final data = widget.requestData;

    final geschaeftsname = (data['geschaeftsname'] ?? '').toString();
    final strassenname = (data['strassenname'] ?? '').toString();
    final hausnummer = (data['hausnummer'] ?? '').toString();
    final plz = (data['plz'] ?? '').toString();
    final stadt = (data['stadt'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final branche = (data['branche'] ?? '').toString();

    _nameController.text = geschaeftsname;
    _emailController.text = email;
    _adresseController.text =
        [strassenname, hausnummer].where((e) => e.trim().isNotEmpty).join(' ');
    _ortController.text = stadt;
    _plzController.text = plz;
    _branche = branche.isEmpty ? null : branche;

    _suchController.text = [
      [strassenname, hausnummer].where((e) => e.trim().isNotEmpty).join(' '),
      plz,
    ].where((e) => e.trim().isNotEmpty).join(', ');
  }

  Future<void> _loadBranchen() async {
    final snap = await FirebaseFirestore.instance.collection('branchen').get();
    final werte = snap.docs.map((doc) {
      final data = doc.data();
      if (data.containsKey('name')) {
        return data['name'].toString();
      }
      return doc.id;
    }).toList();

    werte.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _branchenListe = werte;
      if (_branche != null && !_branchenListe.contains(_branche)) {
        _branchenListe.insert(0, _branche!);
      }
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    final query = input.trim();
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _loadingSuggestions = false;
      });
      return;
    }

    setState(() {
      _loadingSuggestions = true;
    });

    try {
      final url =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(query)}'
          '&language=de'
          '&components=country:de'
          '&key=$apiKey';

      final response = await http.get(Uri.parse(url));
      final data = json.decode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && data['status'] == 'OK') {
        setState(() {
          _suggestions =
          List<Map<String, dynamic>>.from(data['predictions'] ?? []);
          _loadingSuggestions = false;
        });
      } else {
        setState(() {
          _suggestions = [];
          _loadingSuggestions = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _loadingSuggestions = false;
      });
    }
  }

  Future<void> _resolveInitialAddress() async {
    final query = _suchController.text.trim();
    if (query.length < 3) return;

    setState(() {
      _loadingSuggestions = true;
    });

    try {
      final url =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(query)}'
          '&language=de'
          '&components=country:de'
          '&key=$apiKey';

      final response = await http.get(Uri.parse(url));
      final data = json.decode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && data['status'] == 'OK') {
        final predictions =
        List<Map<String, dynamic>>.from(data['predictions'] ?? []);

        setState(() {
          _suggestions = predictions;
          _loadingSuggestions = false;
        });

        if (predictions.isNotEmpty) {
          final firstPlaceId = (predictions.first['place_id'] ?? '').toString();
          if (firstPlaceId.isNotEmpty) {
            await _loadPlaceDetails(firstPlaceId);
          }
        }
      } else {
        setState(() {
          _suggestions = [];
          _loadingSuggestions = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _loadingSuggestions = false;
      });
    }
  }

  Future<void> _loadPlaceDetails(String placeId) async {
    final detailsUrl =
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&language=de'
        '&key=$apiKey';

    final response = await http.get(Uri.parse(detailsUrl));
    final data = json.decode(response.body);

    if (response.statusCode == 200 &&
        data['status'] == 'OK' &&
        data['result'] != null) {
      final result = data['result'];
      final geometry = result['geometry'];
      final addressComponents =
          result['address_components'] as List<dynamic>? ?? [];

      String street = '';
      String streetNumber = '';
      String plz = '';
      String ort = '';

      for (final component in addressComponents) {
        final types = List<String>.from(component['types']);
        if (types.contains('route')) {
          street = component['long_name'];
        } else if (types.contains('street_number')) {
          streetNumber = component['long_name'];
        } else if (types.contains('postal_code')) {
          plz = component['long_name'];
        } else if (types.contains('locality')) {
          ort = component['long_name'];
        }
      }

      final adresse = '$street $streetNumber'.trim();
      final lat = geometry['location']['lat'];
      final lng = geometry['location']['lng'];

      if (!mounted) return;
      setState(() {
        _suchController.text = [
          adresse,
          plz,
        ].where((e) => e.trim().isNotEmpty).join(', ');

        _adresseController.text = adresse;
        _plzController.text = plz;
        _ortController.text = ort;
        _latitudeController.text = lat.toString();
        _longitudeController.text = lng.toString();
        _suggestions = [];
      });
    }
  }

  Future<void> _approveRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = widget.requestId;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final adresse = _adresseController.text.trim();
    final ort = _ortController.text.trim();
    final plz = _plzController.text.trim();
    final branche = (_branche ?? '').trim();

    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());

    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte zuerst einen gültigen Standort prüfen/auswählen.'),
        ),
      );
      return;
    }

    setState(() {
      _isApproving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': name,
        'email': email,
        'adresse': adresse,
        'plz': plz,
        'ort': ort,
        'branche': branche,
        'dienstleisterId': uid,
        'rolle': 'dienstleister',
        'createAt': FieldValue.serverTimestamp(),
        'geo': GeoPoint(latitude, longitude),
        'telefon': (widget.requestData['telefon'] ?? '').toString(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('partner_requests')
          .doc(uid)
          .update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': FirebaseAuth.instance.currentUser?.uid,
        'resolvedName': name,
        'resolvedAdresse': adresse,
        'resolvedOrt': ort,
        'resolvedPlz': plz,
        'resolvedBranche': branche,
        'resolvedGeo': GeoPoint(latitude, longitude),
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dienstleister erfolgreich freigegeben')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler bei der Freigabe: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApproving = false;
        });
      }
    }
  }

  Widget _buildInput({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Partner-Anfrage prüfen',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isApproving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Bitte Standort mit Google Places prüfen und anschließend den Dienstleister freigeben.',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      TextFormField(
                        controller: _suchController,
                        onChanged: _fetchSuggestions,
                        decoration: InputDecoration(
                          hintText: 'Straße, Hausnummer, PLZ suchen',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      if (_loadingSuggestions) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      if (_suggestions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: _suggestions.map((suggestion) {
                              return ListTile(
                                title: Text(
                                  (suggestion['description'] ?? '').toString(),
                                ),
                                onTap: () async {
                                  _suchController.text =
                                      (suggestion['description'] ?? '')
                                          .toString();
                                  final placeId =
                                  (suggestion['place_id'] ?? '').toString();
                                  await _loadPlaceDetails(placeId);
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _buildInput(
                        label: 'Name',
                        controller: _nameController,
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'Bitte Namen eingeben'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      _buildInput(
                        label: 'E-Mail',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'Bitte E-Mail eingeben'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      _buildInput(
                        label: 'Adresse',
                        controller: _adresseController,
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'Bitte Adresse eingeben'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(
                              label: 'Ort',
                              controller: _ortController,
                              validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Bitte Ort eingeben'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInput(
                              label: 'PLZ',
                              controller: _plzController,
                              keyboardType: TextInputType.number,
                              validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Bitte PLZ eingeben'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _branche != null &&
                            _branchenListe.contains(_branche)
                            ? _branche
                            : null,
                        items: _branchenListe.map((value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _branche = value;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Branche',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Bitte Branche wählen'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(
                              label: 'Latitude',
                              controller: _latitudeController,
                              keyboardType: TextInputType.number,
                              validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Bitte Latitude setzen'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInput(
                              label: 'Longitude',
                              controller: _longitudeController,
                              keyboardType: TextInputType.number,
                              validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Bitte Longitude setzen'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isApproving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isApproving ? null : _approveRequest,
                      icon: _isApproving
                          ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.check),
                      label: const Text('Dienstleister freigeben'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}