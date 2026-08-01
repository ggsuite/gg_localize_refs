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
        buffer.write(' ${_scalarToString(value)}\n');
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
        buffer.write('${_scalarToString(item)}\n');
      }
    }
    return buffer.toString();
  } else {
    return '$indentStr${_scalarToString(node)}\n';
  }
}

// .............................................................................
/// Renders [value] as a YAML scalar, quoting a string that would otherwise
/// come back as something else.
///
/// A git `ref` of a ticket branch named »55« is the case that matters: written
/// bare it reads back as an *integer*, and pub rejects the manifest with »The
/// 'ref' field of the description must be a string«. Only strings that need it
/// are quoted, so existing manifests keep their unquoted look.
String _scalarToString(dynamic value) {
  if (value is! String) {
    return '$value';
  }
  return _needsQuotes(value) ? "'${value.replaceAll("'", "''")}'" : value;
}

// .............................................................................
/// Whether [value] must be quoted to survive a YAML round trip as a string.
bool _needsQuotes(String value) {
  // An empty or padded scalar loses its content or its padding.
  if (value.isEmpty || value.trim() != value) {
    return true;
  }

  // Types YAML infers from the text: numbers, booleans, null. Parsers differ
  // in how much of YAML 1.1 they keep (»yes«/»no«/»on«/»off«), so the whole
  // family is quoted rather than guessed at.
  if (num.tryParse(value) != null) {
    return true;
  }
  const typed = <String>{
    'true', 'false', 'yes', 'no', 'on', 'off', 'y', 'n', // booleans
    'null', '~', // null
  };
  if (typed.contains(value.toLowerCase())) {
    return true;
  }

  // Indicator characters are deliberately NOT handled here. Callers pass
  // ready-made YAML fragments through this function as well — a `tag_pattern`
  // arrives as the literal `"{{version}}"`, quotes included — so quoting on a
  // leading `"`, `{` or `-` would nest the quoting and corrupt the value.
  // Only the type of a scalar is repaired, never its syntax.
  return false;
}
