import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Résultat d'une tentative de capture/sélection de photo.
class PhotoCaptureResult {
  /// Chemin relatif stocké en DB. Null si annulé ou erreur.
  final String? path;

  /// Erreur lisible si la capture a échoué (permission refusée, OS error…).
  final String? error;

  const PhotoCaptureResult({this.path, this.error});

  bool get cancelled => path == null && error == null;
}

class PhotoStorage {
  static const String _subdir = 'exercise_photos';

  Future<Directory> _photosDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _subdir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Tente de capturer (caméra) ou choisir (galerie) une photo. Toutes les
  /// erreurs sont attrapées : on remonte un message lisible plutôt que de
  /// laisser l'app se fermer si le picker explose (cas Android 14+ avec
  /// permissions ou FileProvider mal partagés).
  Future<PhotoCaptureResult> capture(String exerciseId,
      {ImageSource? source}) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(
        source: source ?? ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );
    } on Exception catch (e, st) {
      debugPrint('PhotoStorage.capture failed: $e\n$st');
      return PhotoCaptureResult(error: _humanError(e));
    } catch (e, st) {
      debugPrint('PhotoStorage.capture unknown error: $e\n$st');
      return PhotoCaptureResult(error: 'Capture impossible');
    }
    if (picked == null) return const PhotoCaptureResult();
    try {
      final dir = await _photosDir();
      final dest = File(p.join(dir.path, '$exerciseId.jpg'));
      await File(picked.path).copy(dest.path);
      return PhotoCaptureResult(path: p.join(_subdir, '$exerciseId.jpg'));
    } catch (e, st) {
      debugPrint('PhotoStorage.capture copy failed: $e\n$st');
      return const PhotoCaptureResult(error: 'Impossible de sauver la photo');
    }
  }

  String _humanError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('permission')) {
      return "Autorise l'accès à la caméra dans les réglages Android";
    }
    if (msg.contains('camera_access_denied')) {
      return "Accès à la caméra refusé";
    }
    return 'Capture impossible';
  }

  Future<File?> resolve(String? relativePath) async {
    if (relativePath == null) return null;
    final docs = await getApplicationDocumentsDirectory();
    final f = File(p.join(docs.path, relativePath));
    if (await f.exists()) return f;
    return null;
  }

  Future<void> delete(String? relativePath) async {
    if (relativePath == null) return;
    final docs = await getApplicationDocumentsDirectory();
    final f = File(p.join(docs.path, relativePath));
    if (await f.exists()) await f.delete();
  }
}
