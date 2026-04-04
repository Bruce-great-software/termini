import 'package:flutter/material.dart';

class AlleDienstleisterWebShell extends StatefulWidget {
  final Widget child;
  final VoidCallback onPartnerWerdenPressed;
  final VoidCallback onMeinKontoPressed;
  final bool showHeader;

  const AlleDienstleisterWebShell({
    super.key,
    required this.child,
    required this.onPartnerWerdenPressed,
    required this.onMeinKontoPressed,
    required this.showHeader,
  });

  @override
  State<AlleDienstleisterWebShell> createState() =>
      _AlleDienstleisterWebShellState();
}

class _AlleDienstleisterWebShellState extends State<AlleDienstleisterWebShell> {
  static const double _headerFadeDistance = 180;
  double _headerOpacity = 0;

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.showHeader) return false;
    if (notification.depth > 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    final pixels = notification.metrics.pixels;
    final nextOpacity = (pixels / _headerFadeDistance).clamp(0.0, 1.0);
    if ((nextOpacity - _headerOpacity).abs() > 0.01) {
      setState(() {
        _headerOpacity = nextOpacity;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/termini.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Column(
        children: [
          if (widget.showHeader)
            _WebHeader(
              opacity: _headerOpacity,
              onPartnerWerdenPressed: widget.onPartnerWerdenPressed,
              onMeinKontoPressed: widget.onMeinKontoPressed,
            ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebHeader extends StatelessWidget {
  final double opacity;
  final VoidCallback onPartnerWerdenPressed;
  final VoidCallback onMeinKontoPressed;

  const _WebHeader({
    required this.opacity,
    required this.onPartnerWerdenPressed,
    required this.onMeinKontoPressed,
  });

  @override
  Widget build(BuildContext context) {
    final labels = ['Friseur', 'Barbershop', 'Nagelstudio', 'Kosmetikstudio'];

    final bgColor = Color.lerp(Colors.transparent, Colors.white, opacity)!;
    final borderColor =
    Color.lerp(Colors.transparent, const Color(0x14000000), opacity)!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'TERMINI',
            style: TextStyle(
              color: Colors.black,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.6,
              height: 1,
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 34,
                runSpacing: 8,
                children: labels
                    .map(
                      (label) => Text(
                    label,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(width: 24),
          ElevatedButton(
            onPressed: onPartnerWerdenPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Partner werden',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: onMeinKontoPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.person_outline, size: 18),
            label: const Text(
              'Mein Konto',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}