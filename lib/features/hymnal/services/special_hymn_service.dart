import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/special_hymn_model.dart';

class SpecialHymnService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Retorna la referencia a la colección de himnos especiales en Firestore
  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('special_hymns');

  /// Sube un himno nuevo a Firestore
  Future<void> createHymn(SpecialHymn hymn) async {
    await _collection.doc(hymn.id).set(hymn.toJson());
  }

  /// Actualiza un himno existente
  Future<void> updateHymn(SpecialHymn hymn) async {
    await _collection.doc(hymn.id).update(hymn.toJson());
  }

  /// Borra un himno y sus recursos asociados de Firebase Storage
  Future<void> deleteHymn(SpecialHymn hymn) async {
    await _collection.doc(hymn.id).delete();
    
    // Intentar borrar audio
    if (hymn.audioStorageUrl != null) {
      try {
        final ref = _storage.refFromURL(hymn.audioStorageUrl!);
        await ref.delete();
      } catch (e) {
        debugPrint('Error eliminando audio: $e');
      }
    }

    // Intentar borrar partitura
    if (hymn.sheetMusicStorageUrl != null) {
      try {
        final ref = _storage.refFromURL(hymn.sheetMusicStorageUrl!);
        await ref.delete();
      } catch (e) {
        debugPrint('Error eliminando partitura: $e');
      }
    }
  }

  /// Obtiene los himnos de una iglesia específica
  Stream<List<SpecialHymn>> streamHymnsByChurch(String churchId) {
    return _collection
        .where('churchId', isEqualTo: churchId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SpecialHymn.fromJson(doc.data()))
            .toList());
  }

  /// Sube un archivo a Firebase Storage (compatible con Web y Móvil)
  Future<String?> uploadMediaFile({
    required String churchId,
    required String hymnId,
    required String folder,
    required String fileName,
    required Uint8List fileBytes,
    required String contentType,
  }) async {
    try {
      final path = 'special_hymns/$churchId/$hymnId/$folder/$fileName';
      final ref = _storage.ref().child(path);
      
      final uploadTask = ref.putData(
        fileBytes,
        SettableMetadata(contentType: contentType),
      );

      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error subiendo archivo $fileName: $e');
      return null;
    }
  }
}
