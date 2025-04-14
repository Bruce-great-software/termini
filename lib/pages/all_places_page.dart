import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

class AllPlacesPage extends StatefulWidget {
  @override
  _AllPlacesPageState createState() => _AllPlacesPageState();
}

class _AllPlacesPageState extends State<AllPlacesPage> {
  final String apiKey = 'AIzaSyAAydUpc7KvbbEGeUDsw4DF8w2BkpL_Rq0';
  List<dynamic> friseure = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    ladeFriseure();
  }

  Future<void> ladeFriseure() async {
    setState(() => isLoading = true);

    Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high));

    ladeFriseureMitKoordinaten(position.latitude, position.longitude);
  }

  Future<void> ladeFriseureMitKoordinaten(double lat, double lng) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=3000&type=hair_care&keyword=friseur&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);

    if (response.statusCode == 200 && data['status'] == 'OK') {
      setState(() {
        friseure = data['results'];
        isLoading = false;
      });
    } else {
      debugPrint('Fehler: ${data['status']}');
      setState(() => isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getOrtVorschlaege(String input) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&language=de&components=country:de&key=$apiKey';
    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);

    if (response.statusCode == 200 && data['status'] == 'OK') {
      return List<Map<String, dynamic>>.from(data['predictions']);
    } else {
      return [];
    }
  }

  Future<Map<String, dynamic>?> _getKoordinaten(String placeId) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$apiKey';
    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);

    if (response.statusCode == 200 &&
        data['status'] == 'OK' &&
        data['result'] != null) {
      final location = data['result']['geometry']['location'];
      return {
        'lat': location['lat'],
        'lng': location['lng'],
      };
    } else {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Friseure in der Nähe')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TypeAheadField<Map<String, dynamic>>(
              suggestionsCallback: (String pattern) async {
                if (pattern.length < 2) return [];
                return await _getOrtVorschlaege(pattern);
              },
              itemBuilder: (context, suggestion) {
                return ListTile(
                  title: Text(suggestion['description']),
                );
              },
              onSelected: (suggestion) async {
                FocusScope.of(context).unfocus(); // <--- Tastatur schließen
                final placeId = suggestion['place_id'];
                final coords = await _getKoordinaten(placeId);
                if (coords != null) {
                  ladeFriseureMitKoordinaten(coords['lat'], coords['lng']);
                }
              },
              builder: (context, controller, focusNode) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: 'Ort oder PLZ eingeben',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: friseure.length,
              itemBuilder: (context, index) {
                final friseur = friseure[index];
                return ListTile(
                  title: Text(friseur['name'] ?? 'Unbekannt'),
                  subtitle: Text(friseur['vicinity'] ?? 'Keine Adresse'),
                  trailing: Icon(Icons.location_on),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
