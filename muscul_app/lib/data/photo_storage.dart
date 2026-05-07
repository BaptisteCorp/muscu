import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoStorage {
  static const String _subdir = 'exercise_photos';

  Future<Directory> _photosDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _subdir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns the relative path stored in the DB, or null if cancelled.
  Future<String?> capture(String exerciseId, {ImageSource? source}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source ?? ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return null;
    final dir = await _photosDir();
    final dest = File(p.join(dir.path, '$exerciseId.jpg'));
    await File(picked.path).copy(dest.path);
    return p.join(_subdir, '$exerciseId.jpg');
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
