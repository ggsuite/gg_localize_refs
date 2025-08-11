import 'package:gg_localize_refs/src/replace_dependency.dart';
import 'package:test/test.dart';

void main() {
  group('Replace dependency', () {
    group('replaceDependency()', () {
      test('should replace old dependency with new dependency', () {
        String yamlString = '''
dependencies:
  dependency: ^1.0.0
  other_dependency: ^1.0.0
''';

        String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0
  other_dependency: ^1.0.0''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          '^1.0.0',
          '^2.0.0',
        );

        expect(result, equals(expectedYamlString));
      });

      test('should replace old dependency with new '
          'dependency followed by other identation', () {
        String yamlString = '''
dependencies:
  dependency: ^1.0.0

assets:''';

        String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0

assets:''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          '^1.0.0',
          '^2.0.0',
        );

        expect(result, equals(expectedYamlString));
      });

      test('should replace old dependency with comments preserved', () {
        String yamlString = '''
dependencies:
  dependency: ^1.0.0 # Some comment
  other_dependency: ^1.0.0''';

        String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0
  other_dependency: ^1.0.0''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          '^1.0.0',
          '^2.0.0',
        );

        expect(result, equals(expectedYamlString));
      });

      test('should replace multiple occurrences of old dependency', () {
        String yamlString = '''
dependencies:
  dependency: ^1.0.0
  some_other_dependency: ^1.0.0
  x: ^1.0.0
''';

        String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0
  some_other_dependency: ^1.0.0
  x: ^1.0.0''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          '^1.0.0',
          '^2.0.0',
        );

        expect(result, equals(expectedYamlString));
      });

      test('should handle dependencies with complex version constraints', () {
        String yamlString = '''
dependencies:
  dependency: '>=1.0.0 <2.0.0'
''';

        String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          "'>=1.0.0 <2.0.0'",
          '^2.0.0',
        );

        expect(result, equals(expectedYamlString));
      });

      test('should preserve the structure of the yaml file', () {
        String yamlString = '''
dependencies:
  dependency:
    git:
      url: git://github.com/user/repo.git
      ref: master''';

        String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0''';

        String result = replaceDependency(yamlString, 'dependency', '''
git:
  url: git://github.com/user/repo.git
  ref: master
''', '^2.0.0');

        expect(result, equals(expectedYamlString));
      });

      test('should preserve the structure of '
          'the yaml file with multiline replacement', () {
        String yamlString = '''
dependencies:
  dependency: ^2.0.0
''';

        String expectedYamlString = '''
dependencies:
  dependency:
    git:
      url: git://github.com/user/repo.git
      ref: master''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          '^2.0.0',
          '''
git:
  url: git://github.com/user/repo.git
  ref: master
''',
        );

        expect(result, equals(expectedYamlString));
      });

      test(
        'should handle dependencies with leading and trailing whitespace',
        () {
          String yamlString = '''
dependencies:
  dependency: ^1.0.0  


''';

          String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0
''';

          String result = replaceDependency(
            yamlString,
            'dependency',
            '^1.0.0',
            '^2.0.0',
          );

          expect(result, equals(expectedYamlString));
        },
      );

      test('searches only given sectionName when provided', () {
        // Provide dependencies and dev_dependencies with same dep
        String yaml = '''
dependencies:
  a: ^1.0.0

dev_dependencies:
  a: ^1.0.0
''';
        // Replace only in dev_dependencies
        final out = replaceDependency(
          yaml,
          'a',
          '^1.0.0',
          '^2.0.0',
          sectionName: 'dev_dependencies',
        );
        expect(out, '''
dependencies:
  a: ^1.0.0

dev_dependencies:
  a: ^2.0.0''');
      });

      test('keeps empty lines inside block when present', () {
        // Cover branch where child line is empty in _buildReplacementLines
        const yaml = '''
dependencies:
  a:
    git:
      url: x
      ref: y
''';
        const newBlock = 'git:\n  url: x\n\n  ref: y';
        final out = replaceDependency(
          yaml,
          'a',
          'git:\n  url: x\n  ref: y\n',
          newBlock,
        );
        // The empty line should be preserved and indented.
        expect(out, contains('\n\n'));
      });
    });
  });
}
