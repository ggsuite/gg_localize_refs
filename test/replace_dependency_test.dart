import 'package:gg_to_local/src/replace_dependency.dart';
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
  other_dependency: ^1.0.0
''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          '^1.0.0',
          '^2.0.0',
        );

        expect(result, equals(expectedYamlString));
      });

      test(
          'should replace old dependency with new '
          'dependency followed by other identation', () {
        String yamlString = '''
dependencies:
  dependency: ^1.0.0

assets:
''';

        String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0

assets:
''';

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
  other_dependency: ^1.0.0
''';

        String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0
  other_dependency: ^1.0.0
''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          '^1.0.0',
          '^2.0.0',
        );

        expect(result, equals(expectedYamlString));
      });

      test('should not alter yaml when old dependency is not present', () {
        String yamlString = '''
dependencies:
  dependency: ^1.5.0

test: ^1.0.0
''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          '^1.0.0',
          '^2.0.0',
        );

        expect(result, equals(yamlString));
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
  x: ^1.0.0
''';

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
  dependency: ^2.0.0
''';

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
      ref: master
''';

        String expectedYamlString = '''
dependencies:
  dependency: ^2.0.0
''';

        String result = replaceDependency(
          yamlString,
          'dependency',
          '''
  git:
    url: git://github.com/user/repo.git
    ref: master
''',
          '^2.0.0',
        );

        expect(result, equals(expectedYamlString));
      });

      test('should handle dependencies with leading and trailing whitespace',
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
      });
    });
  });
}
