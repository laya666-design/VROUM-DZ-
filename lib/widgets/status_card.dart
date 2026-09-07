import 'package:flutter/material.dart';
import '../services/ocr_service.dart';

class StatusCard extends StatelessWidget {
  final ExpiryStatus status;

  const StatusCard({super.key, required this.status});

  Color get _bgColor {
    switch (status.level) {
      case StatusLevel.ok:
        return const Color(0xFFDCFCE7); // vert clair
      case StatusLevel.warning:
        return const Color(0xFFFEF3C7); // orange clair
      case StatusLevel.expired:
        return const Color(0xFFFEE2E2); // rouge clair
    }
  }

  Color get _fgColor {
    switch (status.level) {
      case StatusLevel.ok:
        return const Color(0xFF166534);
      case StatusLevel.warning:
        return const Color(0xFF92400E);
      case StatusLevel.expired:
        return const Color(0xFF991B1B);
    }
  }

  IconData get _icon {
    switch (status.level) {
      case StatusLevel.ok:
        return Icons.check_circle;
      case StatusLevel.warning:
        return Icons.warning_amber_rounded;
      case StatusLevel.expired:
        return Icons.error;
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _fgColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _fgColor, size: 28),
              const SizedBox(width: 8),
              Text(
                'Expiration : ${_fmt(status.expirationDate)}',
                style: TextStyle(
                  color: _fgColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            status.label,
            style: TextStyle(
              color: _fgColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
