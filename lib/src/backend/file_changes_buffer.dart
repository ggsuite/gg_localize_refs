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
/// Use [add] to queue up changes to files, [addDeletion] to queue up files to
/// be removed, and [apply] to write all changes to disk.
class FileChangesBuffer {
  /// A list of file changes to be applied.
  final List<FileChanges> files = [];

  /// A list of files to be deleted.
  final List<File> deletions = [];

  /// Adds a file and its new content to the buffer.
  ///
  /// [file]: The file to be updated.
  /// [content]: The new content to write to the file.
  void add(File file, String content) {
    files.add(FileChanges(file, content));
  }

  /// Queues [file] for deletion.
  ///
  /// Deleting is a change like any other, so a command that only removes a
  /// file still reports that it changed something (see [isEmpty]).
  void addDeletion(File file) {
    deletions.add(file);
  }

  /// Whether the buffer holds neither a content change nor a deletion.
  bool get isEmpty => files.isEmpty && deletions.isEmpty;

  /// Whether the buffer holds at least one content change or deletion.
  bool get isNotEmpty => !isEmpty;

  /// Applies all buffered file changes by writing the new content to each file
  /// and removing the files queued for deletion.
  ///
  /// If a file already exists,
  /// it will be deleted before writing the new content.
  Future<void> apply() async {
    for (final fileChange in files) {
      await _writeToFile(content: fileChange.content, file: fileChange.file);
    }

    for (final file in deletions) {
      if (await file.exists()) {
        await file.delete();
      }
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
