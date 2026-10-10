import 'package:flutter/foundation.dart';

// Claves públicas de cliente, NO credenciales de usuario. Ambas están
// restringidas a Drive API. La clave web además exige el dominio de CGID.
// No otorgan acceso a archivos privados ni permiten cambios en Drive.
const literatureDriveApiKey = String.fromEnvironment(
  'LITERATURE_DRIVE_API_KEY',
  defaultValue: kIsWeb
      ? 'AIzaSyCtzEURU-is7DwQoK7ixvkRZi4txtDD-W8'
      : 'AIzaSyAWaAx-wBmUlrugpBdv3ylrDeeXPPMx7bU',
);
