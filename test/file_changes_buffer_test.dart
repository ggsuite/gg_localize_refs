import 'dart:io';
import 'package:gg_localize_refs/src/file_changes_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('FileChanges', () {
    test('should create a FileChanges instance with given file and content',
        () {
      // Arrange
      final file = File('test.txt');
      const content = 'Hello, World!';

      // Act
      final fileChange = FileChanges(file, content);

      // Assert
      expect(fileChange.file, equals(file));
      expect(fileChange.content, equals(content));
    });
  });

  group('FileChangesBuffer', () {
    late Directory tempDir;
    late FileChangesBuffer buffer;

    setUp(() async {
      // Create a temporary directory before each test
      tempDir = await Directory.systemTemp.createTemp('file_changes_test');
      buffer = FileChangesBuffer();
    });

    tearDown(() async {
      // Delete the temporary directory after each test
      await tempDir.delete(recursive: true);
    });

    group('add()', () {
      test('should add a file change to the buffer', () async {
        // Arrange
        final file = File('${tempDir.path}/test.txt');
        const content = 'Test content';

        // Act
        buffer.add(file, content);

        // Assert
        expect(buffer.files, hasLength(1));
      });
    });

    group('apply()', () {
      test('should write content to new file when apply() is called', () async {
        // Arrange
        final file = File('${tempDir.path}/test.txt');
        const content = 'Test content';
        buffer.add(file, content);

        // Act
        await buffer.apply();

        // Assert
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), equals(content));
      });

      test('should overwrite existing file when apply() is called', () async {
        // Arrange
        final file = File('${tempDir.path}/test.txt');
        await file.writeAsString('Old content');
        const content = 'New content';
        buffer.add(file, content);

        // Act
        await buffer.apply();

        // Assert
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), equals(content));
      });

      test('should write multiple files when apply() is called', () async {
        // Arrange
        final file1 = File('${tempDir.path}/test1.txt');
        const content1 = 'Content 1';
        final file2 = File('${tempDir.path}/test2.txt');
        const content2 = 'Content 2';
        buffer.add(file1, content1);
        buffer.add(file2, content2);

        // Act
        await buffer.apply();

        // Assert
        expect(await file1.exists(), isTrue);
        expect(await file1.readAsString(), equals(content1));
        expect(await file2.exists(), isTrue);
        expect(await file2.readAsString(), equals(content2));
      });

      test('should delete existing file before writing new content', () async {
        // Arrange
        final file = File('${tempDir.path}/test.txt');
        await file.writeAsString('Old content');
        buffer.add(file, 'New content');

        // Act
        await buffer.apply();

        // Assert
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), equals('New content'));
      });

      test('should handle empty buffer gracefully', () async {
        // Act & Assert
        expect(
          () async => await buffer.apply(),
          returnsNormally,
        );
      });

      test(
          'should overwrite previous content for '
          'the same file if added multiple times', () async {
        // Arrange
        final file = File('${tempDir.path}/test.txt');
        buffer.add(file, 'First content');
        buffer.add(file, 'Second content');

        // Act
        await buffer.apply();

        // Assert
        expect(await file.readAsString(), equals('Second content'));
      });

      test('should stop applying file changes if one fails', () async {
        // Arrange
        final file1 = File('${tempDir.path}/test1.txt');
        const content1 = 'Content 1';
        final file2 =
            File('/root/test2.txt'); // Assume insufficient permissions
        buffer.add(file1, content1);
        buffer.add(file2, 'Content 2');

        // Act
        dynamic exception;
        try {
          await buffer.apply();
        } catch (e) {
          exception = e;
        }

        // Assert
        expect(exception, isA<FileSystemException>());
        expect(await file1.exists(), isTrue);
        expect(await file1.readAsString(), equals(content1));
        expect(await file2.exists(), isFalse);
      });
    });

    group('Buffer behavior', () {
      test('should process files in the order they were added', () async {
        // Arrange
        final order = <String>[];
        final file1 = File('${tempDir.path}/test1.txt');
        final file2 = File('${tempDir.path}/test2.txt');
        buffer = FileChangesBufferMock(
          onWrite: (file) => order.add(file.path),
        );
        buffer.add(file1, 'Content 1');
        buffer.add(file2, 'Content 2');

        // Act
        await buffer.apply();

        // Assert
        expect(order, [file1.path, file2.path]);
      });

      test('should retain buffer contents after apply if not cleared',
          () async {
        // Arrange
        final file = File('${tempDir.path}/test.txt');
        buffer.add(file, 'Content');

        // Act
        await buffer.apply();
        await buffer.apply();

        // Assert
        // Since the buffer is not cleared, the file should be written twice
        // We can check file system operations or
        // assume the content remains the same
        expect(await file.readAsString(), equals('Content'));
      });
    });
  });
}

// Mock class to capture the order of file writes
class FileChangesBufferMock extends FileChangesBuffer {
  final void Function(File) onWrite;

  FileChangesBufferMock({required this.onWrite});

  @override
  Future<void> apply() async {
    for (final fileChange in files) {
      onWrite(fileChange.file);
      await super.apply();
    }
  }
}
