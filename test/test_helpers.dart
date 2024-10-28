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
  Directory dir = Directory.systemTemp.createTempSync(suffix);

  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  expect(dir.existsSync(), isTrue);

  if (folderName == null) {
    return dir;
  }

  Directory newDir = Directory(join(dir.path, folderName));
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
