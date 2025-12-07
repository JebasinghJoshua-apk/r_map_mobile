import 'package:flutter/material.dart';

class ApiKeyMissingBanner extends StatelessWidget {
  const ApiKeyMissingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Text(
        'Provide a Google Places API key using the '
        'GOOGLE_PLACES_API_KEY dart define to enable search.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: Colors.black54),
      ),
    );
  }
}
