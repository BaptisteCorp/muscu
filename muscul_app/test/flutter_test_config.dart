import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

/// Make Drift's NativeDatabase find the system libsqlite3 on Linux during
/// `flutter test`. The Android target uses sqlite3_flutter_libs which bundles
/// its own copy, so this is only needed for desktop test runs.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, () {
      // Try common Ubuntu/Debian locations.
      const candidates = [
        '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
        '/usr/lib/libsqlite3.so.0',
        '/usr/lib64/libsqlite3.so.0',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return DynamicLibrary.open(path);
      }
      return DynamicLibrary.open('libsqlite3.so');
    });
  }
  await testMain();
}
