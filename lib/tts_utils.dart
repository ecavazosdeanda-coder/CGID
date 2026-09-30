/// Utilidad para pre-procesar texto antes de pasarlo al motor TTS (Text-To-Speech).
/// Convierte todas las citas bíblicas a lenguaje natural hablado en español:
/// - "Apocalipsis 10:10" -> "Apocalipsis capítulo 10 versículo 10"
/// - "Apocalipsis 10:10-15" -> "Apocalipsis capítulo 10 versículos 10 al 15"
/// - "1 Pedro 2:9" -> "Primera de Pedro capítulo 2 versículo 9"
/// - "2 Corintios 5:17" -> "Segunda de Corintios capítulo 5 versículo 17"
/// - "3 Juan 1:2" -> "Tercera de Juan capítulo 1 versículo 2"
/// - "Hechos 2:29,34" -> "Hechos capítulo 2 versículos 29 y 34"

/// Convierte la velocidad seleccionada por el usuario al rango esperado por
/// cada motor. Web Speech usa 1.0 como velocidad normal; los motores nativos
/// usados por flutter_tts emplean 0.5 como velocidad normal.
double ttsSpeechRate(double selectedSpeed, {required bool isWeb}) {
  final rate = isWeb ? selectedSpeed : 0.5 * selectedSpeed;
  return rate.clamp(0.1, isWeb ? 10.0 : 1.0).toDouble();
}

/// Normaliza el nombre del libro para la pronunciación hablada natural.
/// Si comienza con "1 ", "2 " o "3 " (ej. "1 Pedro", "2 Corintios", "3 Juan", "1 de Pedro"),
/// se convierte a "Primera de Pedro", "Segunda de Corintios", "Tercera de Juan".
String normalizeBiblicalBookSpoken(String rawBook) {
  var b = rawBook.trim();

  // 1ro / 1ra / 1era / 1 de / 1 ...
  final oneReg = RegExp(
    r'^1\s*(?:(?:era\.?|ra\.?|ero\.?|ro\.?)\s+de|(?:era\.?|ra\.?|ero\.?|ro\.?)|de)?\s+',
    caseSensitive: false,
  );
  if (oneReg.hasMatch(b)) {
    final rest = b.replaceFirst(oneReg, '').trim();
    return 'Primera de $rest';
  }

  // 2do / 2da / 2 de / 2 ...
  final twoReg = RegExp(
    r'^2\s*(?:(?:da\.?|do\.?)\s+de|(?:da\.?|do\.?)|de)?\s+',
    caseSensitive: false,
  );
  if (twoReg.hasMatch(b)) {
    final rest = b.replaceFirst(twoReg, '').trim();
    return 'Segunda de $rest';
  }

  // 3ro / 3ra / 3 de / 3 ...
  final threeReg = RegExp(
    r'^3\s*(?:(?:era\.?|ra\.?|ero\.?|ro\.?)\s+de|(?:era\.?|ra\.?|ero\.?|ro\.?)|de)?\s+',
    caseSensitive: false,
  );
  if (threeReg.hasMatch(b)) {
    final rest = b.replaceFirst(threeReg, '').trim();
    return 'Tercera de $rest';
  }

  return b;
}

String preprocessBiblicalCitations(String text) {
  // Lista exhaustiva y ordenada (más largos primero) de nombres de libros bíblicos en español,
  // incluyendo libros con prefijo numérico (1, 2, 3), variantes de acentos y abreviaturas comunes.
  const bookNames = [
    // Con prefijo numérico
    r'1\s*(?:era\.?|ra\.?|era)?\s+de\s+Cr[oó]nicas',
    r'2\s*(?:da\.?|da)?\s+de\s+Cr[oó]nicas',
    r'1\s*(?:ro\.?|ero\.?|ro)?\s+de\s+Corintios',
    r'2\s*(?:do\.?|do)?\s+de\s+Corintios',
    r'1\s*(?:ro\.?|ero\.?|ro)?\s+de\s+Samuel',
    r'2\s*(?:do\.?|do)?\s+de\s+Samuel',
    r'1\s*(?:ro\.?|ero\.?|ro)?\s+de\s+Reyes',
    r'2\s*(?:do\.?|do)?\s+de\s+Reyes',
    r'1\s*(?:ro\.?|ero\.?|ro)?\s+de\s+Tesalonicenses',
    r'2\s*(?:do\.?|do)?\s+de\s+Tesalonicenses',
    r'1\s*(?:ra\.?|era\.?|ra)?\s+de\s+Timoteo',
    r'2\s*(?:da\.?|da)?\s+de\s+Timoteo',
    r'1\s*(?:ra\.?|era\.?|ra)?\s+de\s+Pedro',
    r'2\s*(?:da\.?|da)?\s+de\s+Pedro',
    r'1\s*(?:ra\.?|era\.?|ra)?\s+de\s+Juan',
    r'2\s*(?:da\.?|da)?\s+de\s+Juan',
    r'3\s*(?:ra\.?|era\.?|ra)?\s+de\s+Juan',
    r'1\s*Cr[oó]nicas',
    r'2\s*Cr[oó]nicas',
    r'1\s*Corintios',
    r'2\s*Corintios',
    r'1\s*Samuel',
    r'2\s*Samuel',
    r'1\s*Reyes',
    r'2\s*Reyes',
    r'1\s*Tesalonicenses',
    r'2\s*Tesalonicenses',
    r'1\s*Timoteo',
    r'2\s*Timoteo',
    r'1\s*Pedro',
    r'2\s*Pedro',
    r'1\s*Juan',
    r'2\s*Juan',
    r'3\s*Juan',
    r'1\s*Cr[oó]n\.?',
    r'2\s*Cr[oó]n\.?',
    r'1\s*Cor\.?',
    r'2\s*Cor\.?',
    r'1\s*Sam\.?',
    r'2\s*Sam\.?',
    r'1\s*Rey\.?',
    r'2\s*Rey\.?',
    r'1\s*Tes\.?',
    r'2\s*Tes\.?',
    r'1\s*Tim\.?',
    r'2\s*Tim\.?',
    r'1\s*Ped?\.?',
    r'2\s*Ped?\.?',
    r'1\s*Jn\.?',
    r'2\s*Jn\.?',
    r'3\s*Jn\.?',

    // Compuestos
    r'Cantar\s+de\s+los\s+Cantares',
    r'Cantares\s+de\s+Salom[oó]n',
    r'Cantares',
    r'Hechos\s+de\s+los\s+Ap[oó]stoles',

    // Libros individuales del Antiguo y Nuevo Testamento
    r'G[eé]nesis',
    r'[EÉ]xodo',
    r'Lev[ií]tico',
    r'N[uú]meros',
    r'Deuteronomio',
    r'Josu[eé]',
    r'Jueces',
    r'Rut',
    r'Esdras',
    r'Nehem[ií]as',
    r'Ester',
    r'Job',
    r'Salmos?',
    r'Proverbios',
    r'Eclesiast[eé]s',
    r'Isa[ií]as',
    r'Jerem[ií]as',
    r'Lamentaciones',
    r'Ezequiel',
    r'Daniel',
    r'Oseas',
    r'Joel',
    r'Am[oó]s',
    r'Abd[ií]as',
    r'Jon[aá]s',
    r'Miqueas',
    r'Nah[uú]m',
    r'Habacuc',
    r'Sofon[ií]as',
    r'Hageo',
    r'Zacar[ií]as',
    r'Malaqu[ií]as',
    r'Mateo',
    r'Marcos',
    r'Lucas',
    r'Juan',
    r'Hechos',
    r'Romanos',
    r'G[aá]latas',
    r'Efesios',
    r'Filipenses',
    r'Colosenses',
    r'Tito',
    r'Filem[oó]n',
    r'Hebreos',
    r'Santiago',
    r'Judas',
    r'Apocalipsis',

    // Abreviaturas comunes
    r'G[eé]n\.?',
    r'[EÉ]x\.?',
    r'Lev\.?',
    r'N[uú]m\.?',
    r'Deut\.?',
    r'Jos\.?',
    r'Jue\.?',
    r'Neh\.?',
    r'Est\.?',
    r'Sal\.?',
    r'Prov\.?',
    r'Ecl\.?',
    r'Isa\.?',
    r'Jer\.?',
    r'Lam\.?',
    r'Ezeq?\.?',
    r'Dan\.?',
    r'Hab\.?',
    r'Zac\.?',
    r'Mal\.?',
    r'Mat\.?',
    r'Mt\.?',
    r'Mar\.?',
    r'Mc\.?',
    r'Luc\.?',
    r'Lc\.?',
    r'Jn\.?',
    r'Hch\.?',
    r'Rom\.?',
    r'G[aá]l\.?',
    r'Efe\.?',
    r'Fil\.?',
    r'Col\.?',
    r'Heb\.?',
    r'Sant?\.?',
    r'Jd\.?',
    r'Apoc?\.?',
  ];

  final booksPattern = bookNames.join('|');

  // 1. Rango de versículos con guion: Libro Cap:Inicio-Fin (ej. "Apocalipsis 10:10-15", "1 Corintios 15:51-54")
  final rangeRegex = RegExp(
    '\\b($booksPattern)\\s+(\\d+):(\\d+)\\s*-\\s*(\\d+)',
    caseSensitive: false,
  );

  var processed = text.replaceAllMapped(rangeRegex, (match) {
    final book = normalizeBiblicalBookSpoken(match.group(1)!);
    final chapter = match.group(2);
    final startVerse = match.group(3);
    final endVerse = match.group(4);
    return '$book capítulo $chapter versículos $startVerse al $endVerse';
  });

  // 2. Versículos separados por coma: Libro Cap:V1,V2 (ej. "Hechos 2:29,34", "Salmo 111:7,8")
  final commaRegex = RegExp(
    '\\b($booksPattern)\\s+(\\d+):(\\d+)\\s*,\\s*(\\d+)',
    caseSensitive: false,
  );

  processed = processed.replaceAllMapped(commaRegex, (match) {
    final book = normalizeBiblicalBookSpoken(match.group(1)!);
    final chapter = match.group(2);
    final v1 = match.group(3);
    final v2 = match.group(4);
    return '$book capítulo $chapter versículos $v1 y $v2';
  });

  // 3. Versículo único: Libro Cap:Versículo (ej. "Apocalipsis 10:10", "1 Pedro 2:9")
  final singleRegex = RegExp(
    '\\b($booksPattern)\\s+(\\d+):(\\d+)(?![-–—])',
    caseSensitive: false,
  );

  processed = processed.replaceAllMapped(singleRegex, (match) {
    final book = normalizeBiblicalBookSpoken(match.group(1)!);
    final chapter = match.group(2);
    final verse = match.group(3);
    return '$book capítulo $chapter versículo $verse';
  });

  // 4. Regla universal de respaldo para libros numerados ("1 Juan 1:9", "2 Reyes 2:11", etc.) o no listados
  final fallbackNumberedRange = RegExp(
    r'\b([123]\s*(?:(?:era\.?|ra\.?|ero\.?|ro\.?|da\.?|do\.?)\s+de|(?:era\.?|ra\.?|ero\.?|ro\.?|da\.?|do\.?)|de)?\s+[A-ZÁÉÍÓÚ][a-záéíóúñ]+)\s+(\d+):(\\d+)\s*-\s*(\\d+)',
    caseSensitive: false,
  );
  processed = processed.replaceAllMapped(fallbackNumberedRange, (match) {
    final book = normalizeBiblicalBookSpoken(match.group(1)!);
    if (book.toLowerCase().contains('capitulo') ||
        book.toLowerCase().contains('capítulo')) {
      return match.group(0)!;
    }
    final chapter = match.group(2);
    final start = match.group(3);
    final end = match.group(4);
    return '$book capítulo $chapter versículos $start al $end';
  });

  final fallbackNumberedSingle = RegExp(
    r'\b([123]\s*(?:(?:era\.?|ra\.?|ero\.?|ro\.?|da\.?|do\.?)\s+de|(?:era\.?|ra\.?|ero\.?|ro\.?|da\.?|do\.?)|de)?\s+[A-ZÁÉÍÓÚ][a-záéíóúñ]+)\s+(\d+):(\\d+)(?![-–—])',
    caseSensitive: false,
  );
  processed = processed.replaceAllMapped(fallbackNumberedSingle, (match) {
    final book = normalizeBiblicalBookSpoken(match.group(1)!);
    if (book.toLowerCase().contains('capitulo') ||
        book.toLowerCase().contains('capítulo')) {
      return match.group(0)!;
    }
    final chapter = match.group(2);
    final verse = match.group(3);
    return '$book capítulo $chapter versículo $verse';
  });

  // 5. Regla universal de respaldo para libros individuales no contemplados
  final fallbackRange = RegExp(
    r'\b([A-ZÁÉÍÓÚ][a-záéíóúñ]+(?:\s+[A-ZÁÉÍÓÚ][a-záéíóúñ]+)*)\s+(\d+):(\d+)\s*-\s*(\d+)',
  );
  processed = processed.replaceAllMapped(fallbackRange, (match) {
    final rawBook = match.group(1)!.trim();
    if (rawBook.toLowerCase().contains('capitulo') ||
        rawBook.toLowerCase().contains('capítulo')) {
      return match.group(0)!;
    }
    final book = normalizeBiblicalBookSpoken(rawBook);
    final chapter = match.group(2);
    final start = match.group(3);
    final end = match.group(4);
    return '$book capítulo $chapter versículos $start al $end';
  });

  final fallbackSingle = RegExp(
    r'\b([A-ZÁÉÍÓÚ][a-záéíóúñ]+(?:\s+[A-ZÁÉÍÓÚ][a-záéíóúñ]+)*)\s+(\d+):(\d+)(?![-–—])',
  );
  processed = processed.replaceAllMapped(fallbackSingle, (match) {
    final rawBook = match.group(1)!.trim();
    if (rawBook.toLowerCase().contains('capitulo') ||
        rawBook.toLowerCase().contains('capítulo')) {
      return match.group(0)!;
    }
    final book = normalizeBiblicalBookSpoken(rawBook);
    final chapter = match.group(2);
    final verse = match.group(3);
    return '$book capítulo $chapter versículo $verse';
  });

  // Una referencia que sigue a punto y coma conserva el libro anterior.
  // Ej.: "Génesis 1:26; 3:22; 11:7". El motor TTS no debe interpretar
  // "3:22" como una hora: siempre representa capítulo y versículo.
  final semicolonRange = RegExp(r';\s*(\d+):(\d+)\s*[-–—]\s*(\d+)');
  processed = processed.replaceAllMapped(semicolonRange, (match) {
    return '; capítulo ${match.group(1)} versículos ${match.group(2)} al ${match.group(3)}';
  });

  final semicolonSingle = RegExp(r';\s*(\d+):(\d+)');
  processed = processed.replaceAllMapped(semicolonSingle, (match) {
    return '; capítulo ${match.group(1)} versículo ${match.group(2)}';
  });

  return processed;
}
