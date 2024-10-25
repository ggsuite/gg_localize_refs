import 'package:gg_to_local/src/yaml_to_string.dart';
import 'package:test/test.dart';

void main() {
  group('yamlToString', () {
    // Test for scalar value
    test('should convert a scalar value to a string', () {
      final result = yamlToString('value');
      expect(result, 'value\n');
    });

    // Test for simple Map with scalar values
    test('should convert a simple Map with scalar values', () {
      final node = {'key1': 'value1', 'key2': 'value2'};
      final result = yamlToString(node);
      expect(result, 'key1: value1\nkey2: value2\n');
    });

    // Test for Map with nested Map
    test('should convert a Map with nested Map', () {
      final node = {
        'key1': 'value1',
        'key2': {
          'nestedKey1': 'nestedValue1',
          'nestedKey2': 'nestedValue2',
        },
      };
      final result = yamlToString(node);
      const expected = '''
key1: value1
key2:
  nestedKey1: nestedValue1
  nestedKey2: nestedValue2
''';
      expect(result, expected);
    });

    // Test for List with scalar values
    test('should convert a List with scalar values', () {
      final node = ['value1', 'value2', 'value3'];
      final result = yamlToString(node);
      const expected = '''
- value1
- value2
- value3
''';
      expect(result, expected);
    });

    // Test for List with nested Maps
    test('should convert a List with nested Maps', () {
      final node = [
        {'key1': 'value1'},
        {'key2': 'value2'},
      ];
      final result = yamlToString(node);
      const expected = '''
- 
  key1: value1
- 
  key2: value2
''';
      expect(result, expected);
    });

    // Test for empty Map
    test('should convert an empty Map', () {
      final node = <String, dynamic>{};
      final result = yamlToString(node);
      expect(result, '');
    });

    // Test for empty List
    test('should convert an empty List', () {
      final node = <String>[];
      final result = yamlToString(node);
      expect(result, '');
    });

    // Test for complex nested structure
    test('should convert a complex nested structure', () {
      final node = {
        'key1': 'value1',
        'key2': [
          'item1',
          {'nestedKey1': 'nestedValue1'},
          ['subItem1', 'subItem2'],
        ],
        'key3': {
          'key4': 'value4',
        },
      };
      final result = yamlToString(node);
      const expected = '''
key1: value1
key2:
  - item1
  - 
    nestedKey1: nestedValue1
  - 
    - subItem1
    - subItem2
key3:
  key4: value4
''';
      expect(result, expected);
    });

    // Test for null values in Map
    test('should handle null values in Map', () {
      final node = {'key1': null};
      final result = yamlToString(node);
      expect(result, 'key1: null\n');
    });

    // Test for null values in List
    test('should handle null values in List', () {
      final node = [null];
      final result = yamlToString(node);
      expect(result, '- null\n');
    });

    // Test for Map with various data types
    test('should convert Map with various data types', () {
      final node = {
        'int': 42,
        'double': 3.14,
        'bool': true,
        'null': null,
        'string': 'text',
      };
      final result = yamlToString(node);
      const expected = '''
int: 42
double: 3.14
bool: true
null: null
string: text
''';
      expect(result, expected);
    });

    // Test for List with mixed data types
    test('should convert a List with mixed data types', () {
      final node = [
        'text',
        123,
        true,
        null,
        {'key': 'value'},
      ];
      final result = yamlToString(node);
      const expected = '''
- text
- 123
- true
- null
- 
  key: value
''';
      expect(result, expected);
    });

    // Test with custom indent level
    test('should respect custom indent level', () {
      final node = {'key': 'value'};
      final result = yamlToString(node, 2);
      expect(result, '    key: value\n');
    });

    // Test for Map containing List
    test('should convert a Map containing a List', () {
      final node = {
        'key1': 'value1',
        'key2': ['listItem1', 'listItem2'],
      };
      final result = yamlToString(node);
      const expected = '''
key1: value1
key2:
  - listItem1
  - listItem2
''';
      expect(result, expected);
    });

    // Test for deeply nested structures
    test('should convert deeply nested structures', () {
      final node = {
        'level1': {
          'level2': {
            'level3': {
              'level4': 'deepValue',
            },
          },
        },
      };
      final result = yamlToString(node);
      const expected = '''
level1:
  level2:
    level3:
      level4: deepValue
''';
      expect(result, expected);
    });

    // Test for List containing List
    test('should convert a List containing another List', () {
      final node = [
        'item1',
        ['subItem1', 'subItem2'],
      ];
      final result = yamlToString(node);
      const expected = '''
- item1
- 
  - subItem1
  - subItem2
''';
      expect(result, expected);
    });

    // Test for special characters in strings
    test('should handle strings with special characters', () {
      final node = {'key:with:colons': 'value with \n newlines'};
      final result = yamlToString(node);
      expect(result, 'key:with:colons: value with \n newlines\n');
    });

    // Test for Unicode characters
    test('should handle Unicode characters', () {
      final node = {'emoji': '😀', 'language': '中文'};
      final result = yamlToString(node);
      const expected = '''
emoji: 😀
language: 中文
''';
      expect(result, expected);
    });

    // Test for large data structure
    test('should convert a large data structure', () {
      final node = {
        'users': [
          {
            'id': 1,
            'name': 'Alice',
            'roles': ['admin', 'user'],
          },
          {
            'id': 2,
            'name': 'Bob',
            'roles': ['user'],
          },
        ],
      };
      final result = yamlToString(node);
      const expected = '''
users:
  - 
    id: 1
    name: Alice
    roles:
      - admin
      - user
  - 
    id: 2
    name: Bob
    roles:
      - user
''';
      expect(result, expected);
    });
  });
}
