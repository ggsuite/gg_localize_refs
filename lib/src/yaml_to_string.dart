// ...........................................................................
/// Convert a YAML node to a string
String yamlToString(dynamic node, [int indent = 0]) {
  final String indentStr = '  ' * indent;
  if (node is Map) {
    StringBuffer buffer = StringBuffer();
    node.forEach((key, value) {
      buffer.write('$indentStr$key:');
      if (value is Map || value is List) {
        buffer.write('\n');
        buffer.write(yamlToString(value, indent + 1));
      } else {
        buffer.write(' $value\n');
      }
    });
    return buffer.toString();
  } else if (node is List) {
    StringBuffer buffer = StringBuffer();
    for (var item in node) {
      buffer.write('$indentStr- ');
      if (item is Map || item is List) {
        buffer.write('\n');
        buffer.write(yamlToString(item, indent + 1));
      } else {
        buffer.write('$item\n');
      }
    }
    return buffer.toString();
  } else {
    return '$indentStr$node\n';
  }
}
