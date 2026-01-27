import 'dart:io';

/// A class representing changes to be made to a file.
///
/// Contains the [file] object and the new [content] to be written to the file.
class FileChanges {
  /// The file to be updated.
  final File file;

  /// The new content to write to the file.
  final String content;

  /// Creates a [FileChanges] instance with the given [file] and [content].
  ///
  /// - [file]: The file that will be modified.
  /// - [content]: The content to write to the file.
  FileChanges(this.file, this.content);
}

/// A buffer that collects file changes and applies them all at once.
///
/// Use [add] to queue up changes to files,
/// and [apply] to write all changes to disk.
class FileChangesBuffer {
  /// A list of file changes to be applied.
  final List<FileChanges> files = [];

  /// Adds a file and its new content to the buffer.
  ///
  /// [file]: The file to be updated.
  /// [content]: The new content to write to the file.
  void add(File file, String content) {
    files.add(FileChanges(file, content));
  }

  /// Applies all buffered file changes by writing the new content to each file.
  ///
  /// If a file already exists,
  /// it will be deleted before writing the new content.
  Future<void> apply() async {
    for (final fileChange in files) {
      await _writeToFile(content: fileChange.content, file: fileChange.file);
    }
  }
}

// ...........................................................................
/// Helper method to write content to a file
Future<void> _writeToFile({required String content, required File file}) async {
  if (await file.exists()) {
    await file.delete();
  }
  await file.writeAsString(content);
}
