/// Convierte enlaces compartidos de archivos en URLs estables para Drive.
/// No solicita tokens, no cambia permisos y no copia el PDF a Firebase.
class DriveDocumentLink {
  const DriveDocumentLink(this.fileId, {this.resourceKey});
  final String fileId;
  final String? resourceKey;

  static bool isDriveHost(String host) =>
      host == 'drive.google.com' || host == 'docs.google.com';

  static DriveDocumentLink? tryParse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        !isDriveHost(uri.host) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    String? id;
    final segments = uri.pathSegments;
    if (segments.length >= 3 && segments[0] == 'file' && segments[1] == 'd') {
      id = segments[2];
    } else if (uri.path == '/open' || uri.path == '/uc') {
      id = uri.queryParameters['id'];
    }
    if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{10,200}$').hasMatch(id)) {
      return null;
    }
    final key = uri.queryParameters['resourcekey'];
    if (key != null && !RegExp(r'^[a-zA-Z0-9_-]{1,200}$').hasMatch(key)) {
      return null;
    }
    return DriveDocumentLink(id, resourceKey: key);
  }

  Uri _uri(String action) => Uri.https(
    'drive.google.com',
    '/file/d/$fileId/$action',
    resourceKey == null ? null : {'resourcekey': resourceKey!},
  );
  Uri get viewUri => _uri('view');
}

String normalizeLiteratureUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    throw ArgumentError('Ingresa un enlace HTTPS público al PDF.');
  }
  if (DriveDocumentLink.isDriveHost(uri.host)) {
    final link = DriveDocumentLink.tryParse(value);
    if (link == null) {
      throw ArgumentError(
        'Pega el enlace de un archivo PDF de Drive, no de una carpeta ni de un documento de Google Docs.',
      );
    }
    return link.viewUri.toString();
  }
  return uri.toString();
}
