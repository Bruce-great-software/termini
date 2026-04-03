import 'package:flutter/material.dart';

class PartnerWerdenPage extends StatefulWidget {
  const PartnerWerdenPage({super.key});

  @override
  State<PartnerWerdenPage> createState() => _PartnerWerdenPageState();
}

class _PartnerWerdenPageState extends State<PartnerWerdenPage> {
  // Geschäft
  final TextEditingController geschaeftController = TextEditingController();
  final TextEditingController strasseController = TextEditingController();
  final TextEditingController hausnummerController = TextEditingController();
  final TextEditingController plzController = TextEditingController();
  final TextEditingController stadtController = TextEditingController();

  // Eigentümer
  final TextEditingController vornameController = TextEditingController();
  final TextEditingController nachnameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController telefonController = TextEditingController();

  String? branche;

  final List<String> branchenListe = [
    "Friseur",
    "Barbershop",
    "Kosmetikstudio",
    "Nagelstudio",
    "Massage",
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Partner werden"),
        elevation: 0,
      ),
      body: isWide
          ? Row(
        children: [
          Expanded(child: _buildLeftSide()),
          Expanded(child: _buildForm()),
        ],
      )
          : SingleChildScrollView(
        child: Column(
          children: [
            _buildLeftSide(),
            _buildForm(),
          ],
        ),
      ),
    );
  }

  // 🔹 LINKER BEREICH
  Widget _buildLeftSide() {
    return Container(
      padding: const EdgeInsets.all(40),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SizedBox(height: 40),
          Text(
            "Gewinne neue Kunden\nmit TERMINI",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 20),
          Text(
            "• Online Termine verwalten\n"
                "• Mehr Sichtbarkeit in deiner Region\n"
                "• Weniger Telefonstress\n"
                "• Modernes Buchungssystem",
            style: TextStyle(
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // 🔹 FORMULAR
  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Jetzt Partner werden",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),

          // 🔹 Geschäftsinformationen
          const Text(
            "Geschäftsinformationen",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),

          _buildInput("Name des Geschäfts", geschaeftController),
          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: _buildInput("Straßenname", strasseController),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildInput("Hausnummer", hausnummerController),
              ),
            ],
          ),
          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: _buildInput("PLZ", plzController),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildInput("Stadt", stadtController),
              ),
            ],
          ),
          const SizedBox(height: 15),

          DropdownButtonFormField<String>(
            value: branche,
            hint: const Text("Branche wählen"),
            items: branchenListe.map((b) {
              return DropdownMenuItem(
                value: b,
                child: Text(b),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                branche = value;
              });
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 30),

          // 🔹 Eigentümerinformationen
          const Text(
            "Eigentümerinformationen",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: _buildInput("Vorname", vornameController),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildInput("Nachname", nachnameController),
              ),
            ],
          ),
          const SizedBox(height: 15),

          _buildInput("E-Mail", emailController),
          const SizedBox(height: 15),

          _buildInput("Telefonnummer", telefonController),
          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Antrag gesendet (Demo)"),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text("Jetzt Partner werden"),
            ),
          ),
        ],
      ),
    );
  }

  // 🔹 INPUT
  Widget _buildInput(String hint, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}