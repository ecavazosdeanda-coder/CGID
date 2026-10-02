import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioDownloadProgress {
  final double progress; // 0.0 a 1.0
  final String status;
  final int bytesDownloaded;
  final int totalBytes;

  AudioDownloadProgress({
    required this.progress,
    required this.status,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
  });
}

class AudioManager {
  static final AudioManager instance = AudioManager._internal();
  AudioManager._internal();

  static const String defaultAudioZipUrl =
      'https://drive.google.com/file/d/1KQK-5TYibQ_09JQE79pGc-Gj2zdqw_Me/view?usp=sharing';
  static const String prefUrlKey = 'custom_audio_zip_url';

  Directory? _audioDir;
  http.Client? _activeClient;
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  Future<Directory> getAudioDirectory() async {
    if (_audioDir != null && await _audioDir!.exists()) {
      return _audioDir!;
    }
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/cgid_audios');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _audioDir = dir;
    return dir;
  }

  String _cleanTrackName(String track) {
    var name = track.trim();
    if (name.startsWith('audio/')) {
      name = name.substring('audio/'.length);
    } else if (name.startsWith('assets/audio/')) {
      name = name.substring('assets/audio/'.length);
    }
    return name;
  }

  Future<File?> getLocalAudioFile(String track) async {
    try {
      final dir = await getAudioDirectory();
      final filename = _cleanTrackName(track);

      // Intentar buscar el archivo directamente
      final directFile = File('${dir.path}/$filename');
      if (await directFile.exists() && await directFile.length() > 0) {
        return directFile;
      }

      // Si no, extraer el número del himno (ej. h1.mp3 -> 1, hrecording100.mp3 -> 100)
      // y buscar el archivo real extraído del ZIP (ej. "1. A MI SALVADOR.mp3" o "1.- A mi Salvador.mp3")
      final match = RegExp(r'^h(?:recording)?(\d+)\.mp3$').firstMatch(filename);
      if (match != null) {
        final numInt = int.tryParse(match.group(1)!);
        if (numInt != null) {
          final files = dir.listSync();
          for (final f in files) {
            if (f is File) {
              final fname = f.path.split('/').last.split('\\').last;
              final fMatch = RegExp(r'^(\d+)\s*[-.]').firstMatch(fname);
              if (fMatch != null && int.tryParse(fMatch.group(1)!) == numInt) {
                if (await f.length() > 0) return f;
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> hasLocalAudio(String track) async {
    final file = await getLocalAudioFile(track);
    return file != null;
  }

  Future<int> countDownloadedAudios() async {
    try {
      final dir = await getAudioDirectory();
      if (!await dir.exists()) return 0;
      final files = dir.listSync();
      var count = 0;
      for (final f in files) {
        if (f is File && f.path.toLowerCase().endsWith('.mp3')) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<int> getDownloadedBytes() async {
    try {
      final dir = await getAudioDirectory();
      if (!await dir.exists()) return 0;
      final files = dir.listSync();
      var total = 0;
      for (final f in files) {
        if (f is File) {
          total += await f.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefUrlKey) ?? defaultAudioZipUrl;
  }

  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefUrlKey, url.trim());
  }

  Future<void> deleteDownloadedAudios() async {
    try {
      final dir = await getAudioDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _audioDir = null;
      }
    } catch (_) {}
  }

  void cancelDownload() {
    _activeClient?.close();
    _activeClient = null;
    _isDownloading = false;
  }

  Stream<AudioDownloadProgress> downloadAudioZip({String? customUrl}) async* {
    if (_isDownloading) {
      throw StateError('Ya hay una descarga en curso.');
    }

    _isDownloading = true;
    _activeClient = http.Client();
    final targetDir = await getAudioDirectory();
    final urlStr = customUrl ?? await getServerUrl();

    try {
      yield AudioDownloadProgress(
        progress: 0.0,
        status: 'Conectando con el servidor…',
      );

      var finalUrlStr = urlStr;
      final driveRegex = RegExp(r'drive\.google\.com/file/d/([a-zA-Z0-9_-]+)');
      final match = driveRegex.firstMatch(urlStr);
      if (match != null) {
        finalUrlStr =
            'https://drive.google.com/uc?export=download&id=${match.group(1)}';
      } else if (urlStr.contains('drive.google.com/open')) {
        final idMatch = RegExp(r'id=([a-zA-Z0-9_-]+)').firstMatch(urlStr);
        if (idMatch != null) {
          finalUrlStr =
              'https://drive.google.com/uc?export=download&id=${idMatch.group(1)}';
        }
      }

      final uri = Uri.parse(finalUrlStr);
      final request = http.Request('GET', uri);
      var response = await _activeClient!.send(request);

      // Si Google Drive devuelve una página HTML de advertencia de virus (archivos grandes)
      if (response.statusCode == 200 &&
          response.headers['content-type']?.contains('text/html') == true) {
        final htmlContent = await response.stream.bytesToString();

        // Buscar el formulario de confirmación en el HTML
        final actionMatch = RegExp(r'action="([^"]+)"').firstMatch(htmlContent);
        final uuidMatch = RegExp(r'name="uuid"\s+value="([^"]+)"')
            .firstMatch(htmlContent);

        if (actionMatch != null) {
          var newUrl = actionMatch.group(1)!;
          if (newUrl.startsWith('/')) {
            newUrl = 'https://drive.google.com$newUrl';
          }
          final uuidParam = uuidMatch != null
              ? '&uuid=${uuidMatch.group(1)}'
              : '';

          final idMatch = RegExp(r'id=([a-zA-Z0-9_-]+)')
              .firstMatch(finalUrlStr);
          final idParam = idMatch != null ? '?id=${idMatch.group(1)}' : '';

          final confirmUrl =
              '$newUrl$idParam&export=download&confirm=t$uuidParam';

          response = await _activeClient!.send(
            http.Request('GET', Uri.parse(confirmUrl)),
          );
        } else {
          throw StateError(
            'No se pudo encontrar el enlace directo en Google Drive.',
          );
        }
      }

      if (response.statusCode != 200) {
        throw StateError(
          'El servidor respondió con error ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      final contentLength = response.contentLength ?? 0;
      final tempZipFile = File('${targetDir.path}/temp_audios.zip');
      final ios = tempZipFile.openWrite();
      var receivedBytes = 0;

      await for (final chunk in response.stream) {
        if (!_isDownloading) {
          await ios.close();
          if (tempZipFile.existsSync()) tempZipFile.deleteSync();
          throw StateError('Descarga cancelada.');
        }
        ios.add(chunk);
        receivedBytes += chunk.length;

        final ratio = contentLength > 0 ? (receivedBytes / contentLength) : 0.0;
        final mbDownloaded = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
        final mbTotal = contentLength > 0
            ? (contentLength / (1024 * 1024)).toStringAsFixed(1)
            : '?';

        yield AudioDownloadProgress(
          progress: ratio.clamp(
            0.0,
            0.95,
          ), // 95% para descarga, 5% descompresión
          status:
              'Descargando: $mbDownloaded MB de $mbTotal MB (${(ratio * 100).toStringAsFixed(0)}%)',
          bytesDownloaded: receivedBytes,
          totalBytes: contentLength,
        );
      }

      await ios.flush();
      await ios.close();

      yield AudioDownloadProgress(
        progress: 0.96,
        status: 'Descomprimiendo archivos de audio (esto tomará un momento)…',
        bytesDownloaded: receivedBytes,
        totalBytes: contentLength,
      );

      // Decodificación y extracción en disco sin cargar el ZIP a RAM
      final extractedCount = await compute(_extractZipOnDisk, {
        'zipPath': tempZipFile.path,
        'targetPath': targetDir.path,
      });

      if (tempZipFile.existsSync()) tempZipFile.deleteSync();

      yield AudioDownloadProgress(
        progress: 1.0,
        status: '¡Listo! Se instalaron $extractedCount himnos con éxito.',
        bytesDownloaded: receivedBytes,
        totalBytes: contentLength,
      );
    } catch (e) {
      // Limpiar archivo temporal si falla
      try {
        final targetDir = await getAudioDirectory();
        final tempZipFile = File('${targetDir.path}/temp_audios.zip');
        if (tempZipFile.existsSync()) tempZipFile.deleteSync();
      } catch (_) {}

      if (!_isDownloading) {
        yield AudioDownloadProgress(
          progress: 0.0,
          status: 'Descarga cancelada.',
        );
      } else {
        rethrow;
      }
    } finally {
      _isDownloading = false;
      _activeClient?.close();
      _activeClient = null;
    }
  }

  static int _extractZipOnDisk(Map<String, String> args) {
    final zipPath = args['zipPath']!;
    final targetPath = args['targetPath']!;

    final inputStream = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(inputStream);

    var extractedCount = 0;
    for (final file in archive) {
      if (file.isFile) {
        final filename = file.name.split('/').last.split('\\').last;
        if (filename.toLowerCase().endsWith('.mp3')) {
          final outFile = File('$targetPath/$filename');
          final outputStream = OutputFileStream(outFile.path);
          file.writeContent(outputStream);
          outputStream.close();
          extractedCount++;
        }
      }
    }
    inputStream.close();

    return extractedCount;
  }

  static const String defaultDriveApiKey =
      'AIzaSyBpM3uw3U_Gn_0pTy9yqob5Vosq9iB2Cig';
  static const String defaultDriveFolderId =
      '1VC5OmPHMEZrQbIAlDsHIjAnh6DAXnfei';

  Future<String?> getDriveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('drive_api_key') ?? defaultDriveApiKey;
  }

  Future<void> setDriveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('drive_api_key', key.trim());
  }

  Future<String?> getDriveFolderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('drive_folder_id') ?? defaultDriveFolderId;
  }

  Future<void> setDriveFolderId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('drive_folder_id', id.trim());
  }

  Future<File?> downloadSingleAudioFromDrive(
    String track,
    String apiKey,
  ) async {
    final folderId = await getDriveFolderId();
    if (folderId == null || folderId.isEmpty) return null;

    final targetName = _cleanTrackName(track);

    // 1. Search for the file in the Drive folder
    final queryUrl = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=\'$folderId\'+in+parents+and+trashed=false&fields=files(id,name)&key=$apiKey',
    );

    final searchResponse = await http.get(queryUrl);
    if (searchResponse.statusCode != 200) {
      throw StateError('Error de API: ${searchResponse.statusCode}');
    }

    final data = jsonDecode(searchResponse.body);
    final files = data['files'] as List;
    String? fileId;

    for (final f in files) {
      if (f['name'] == targetName) {
        fileId = f['id'];
        break;
      }
    }

    if (fileId == null) return null;

    // 2. Download the file
    final downloadUrl = Uri.parse(
      'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=$apiKey',
    );
    final downloadResponse = await http.get(downloadUrl);

    if (downloadResponse.statusCode == 200) {
      final dir = await getAudioDirectory();
      final file = File('${dir.path}/$targetName');
      await file.writeAsBytes(downloadResponse.bodyBytes);
      return file;
    }

    return null;
  }
}
