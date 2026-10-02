import 'package:flutter/material.dart';

Widget buildDigitalScoreView(String source, {required bool dark}) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 560),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 52),
            const SizedBox(height: 14),
            const Text(
              'La partitura limpia MusicXML está disponible en la versión web.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'En este dispositivo puedes consultar la partitura original con el botón inferior.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  ),
);
