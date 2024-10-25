import 'dart:io';

import 'package:gg_to_local/src/process_dependencies.dart';
import 'package:test/test.dart';

void main() {
  group('Process dependencies', () {
    group('Helper methods', () {
      group('correctDir()', () {
        test('succeeds', () {
          expect(
            correctDir(Directory('test/')).path,
            'test',
          );
          expect(
            correctDir(Directory('test/.')).path,
            'test',
          );
        });
      });

      group('getPackageName()', () {
        group('should throw', () {
          test('when pubspec.yaml cannot be parsed', () async {
            expect(
              () => getPackageName('invalid yaml'),
              throwsA(
                isA<Exception>().having(
                  (e) => e.toString(),
                  'message',
                  contains('Error parsing pubspec.yaml'),
                ),
              ),
            );
          });
        });
      });
    });
  });
}
