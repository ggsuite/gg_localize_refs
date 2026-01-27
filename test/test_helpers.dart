import 'dart:io';

import 'package:path/path.dart';
import 'package:test/test.dart';

void createDirs(List<Directory> dirs) {
  for (final dir in dirs) {
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    expect(dir.existsSync(), isTrue);
  }
}

Directory createTempDir(String suffix, [String? folderName]) {
  final dir = Directory.systemTemp.createTempSync(suffix);

  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  expect(dir.existsSync(), isTrue);

  if (folderName == null) {
    return dir;
  }

  final newDir = Directory(join(dir.path, folderName));
  if (!newDir.existsSync()) {
    newDir.createSync(recursive: true);
  }
  expect(newDir.existsSync(), isTrue);

  return newDir;
}

void deleteDirs(List<Directory> dirs) {
  for (final dir in dirs) {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    expect(dir.existsSync(), isFalse);
  }
}

/// Recursively copy the contents of [source] into [destination].
///
/// Existing files in [destination] will be overwritten.
void copyDirectory(Directory source, Directory destination) {
  if (!source.existsSync()) {
    throw ArgumentError('Source directory does not exist: ${source.path}');
  }

  if (!destination.existsSync()) {
    destination.createSync(recursive: true);
  }

  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relativePath = relative(entity.path, from: source.path);
    final newPath = join(destination.path, relativePath);

    if (entity is Directory) {
      final newDir = Directory(newPath);
      if (!newDir.existsSync()) {
        newDir.createSync(recursive: true);
      }
    } else if (entity is File) {
      final newFile = File(newPath);
      newFile
        ..createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}
