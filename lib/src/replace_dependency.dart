// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights
// Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Replaces a dependency entry in pubspec.yaml content.
///
/// This function performs a structural, line-based replacement to avoid
/// duplicate keys and to properly remove old block entries.
///
/// Parameters:
/// - yamlString: The complete YAML content.
/// - depName: The dependency name to replace.
/// - oldDep: Deprecated. Kept for backward compatibility. Not used.
/// - newDep: The new value. If it is a single-line scalar without ':'
///   it will be written as "depName: value". Otherwise it is treated as
///   a block placed under the key "depName:".
/// - sectionName: Optional section where the dependency lives.
///   Either 'dependencies' or 'dev_dependencies'. If null the function
///   searches 'dependencies' first and then 'dev_dependencies'.
String replaceDependency(
  String yamlString,
  String depName,
  String oldDep,
  String newDep, {
  String? sectionName,
}) {
  final lines = _splitLines(yamlString);

  final sectionsToSearch = sectionName == null
      ? <String>['dependencies', 'dev_dependencies']
      : <String>[sectionName];

  for (final section in sectionsToSearch) {
    final secRange = _findSectionRange(lines, section);
    if (secRange == null) {
      continue;
    }

    final depRange = _findDependencyRangeInSection(
      lines,
      secRange.start,
      secRange.end,
      depName,
    );
    if (depRange == null) {
      continue;
    }

    final replacement = _buildReplacementLines(depName, newDep);

    // Replace the range with the new lines.
    lines.replaceRange(depRange.start, depRange.end, replacement);

    // Clean up possible duplicate empty lines.
    _collapseExtraEmptyLines(lines);

    return lines.join('\n');
  }

  // If we reach here, nothing was replaced.
  return yamlString;
}

// ...........................................................................
/// Range helper class with start (inclusive) and end (exclusive)
class _Range {
  _Range(this.start, this.end);
  final int start;
  final int end;
}

// ...........................................................................
/// Split text into lines preserving empty trailing lines properly.
List<String> _splitLines(String text) {
  // Normalize Windows line endings to \n first.
  text = text.replaceAll('\r\n', '\n');
  text = text.replaceAll('\r', '\n');
  // Split on \n. Keep empty last if present.
  final parts = text.split('\n');
  if (text.endsWith('\n')) {
    // Remove the trailing empty element added by split since join will
    // reinsert newlines. We prefer to handle trailing newlines by content.
    if (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }
  }
  return parts;
}

// ...........................................................................
/// Find a top-level section like 'dependencies:'
_Range? _findSectionRange(List<String> lines, String sectionName) {
  final sectionHeader = '$sectionName:';
  int? start;
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_indentOf(line) == 0 && line.trim() == sectionHeader) {
      start = i;
      break;
    }
  }
  if (start == null) {
    return null;
  }

  // Section content starts after header.
  int end = lines.length;
  for (int i = start + 1; i < lines.length; i++) {
    final ind = _indentOf(lines[i]);
    // A new top-level section starts with indent 0 and ends current.
    if (ind == 0 && lines[i].trim().endsWith(':')) {
      end = i;
      break;
    }
  }
  // The usable range for items is from start+1 to end.
  // Include the header line because we need it for context when replacing.
  return _Range(start, end);
}

// ...........................................................................
/// Find the dependency range inside a section.
/// Returns the start (inclusive) and end (exclusive) indices.
_Range? _findDependencyRangeInSection(
  List<String> lines,
  int sectionStart,
  int sectionEnd,
  String depName,
) {
  // Items are expected to be indented with two spaces relative to section.
  // Section header is at sectionStart, items begin at sectionStart+1.
  const itemIndent = 2;
  for (int i = sectionStart + 1; i < sectionEnd; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      continue;
    }
    final ind = _indentOf(line);
    if (ind != itemIndent) {
      // Different indent, not a top-level item of this section.
      continue;
    }

    // Match either "depName:" or "depName: value".
    final trimmed = line.trimLeft();
    if (!trimmed.startsWith('$depName:')) {
      continue;
    }

    // Determine if scalar or block.
    final afterColon = trimmed.substring(depName.length + 1);
    final hasInlineValue = afterColon.trim().isNotEmpty;

    if (hasInlineValue) {
      // Scalar in a single line.
      return _Range(i, i + 1);
    }

    // Block: find end where indent drops back to itemIndent or less,
    // or we reach sectionEnd.
    int j = i + 1;
    for (; j < sectionEnd; j++) {
      final indJ = _indentOf(lines[j]);
      if (lines[j].trim().isEmpty) {
        // Keep empty lines inside the block until pattern changes.
        continue;
      }
      if (indJ <= itemIndent) {
        break;
      }
    }
    return _Range(i, j);
  }
  return null;
}

// ...........................................................................
/// Build replacement lines for the dependency.
List<String> _buildReplacementLines(String depName, String newDep) {
  newDep = newDep.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  newDep = newDep.trimRight();

  // Scalar if single line without colon.
  final isScalar = !newDep.contains('\n') && !newDep.contains(':');

  if (isScalar) {
    // Two spaces indent for section items.
    return ['  $depName: $newDep'];
  }

  // Treat as block. Ensure the child lines are indented by 4 spaces.
  final child = newDep.split('\n');
  final indentedChild = <String>[];
  for (final l in child) {
    if (l.isEmpty) {
      indentedChild.add('');
    } else {
      indentedChild.add('    $l');
    }
  }
  return ['  $depName:', ...indentedChild];
}

// ...........................................................................
/// Compute the indent (number of leading spaces) of a line.
int _indentOf(String line) {
  int i = 0;
  while (i < line.length && line[i] == ' ') {
    i++;
  }
  return i;
}

// ...........................................................................
/// Collapse consecutive empty lines to at most one.
void _collapseExtraEmptyLines(List<String> lines) {
  for (int i = lines.length - 2; i >= 0; i--) {
    if (lines[i].trim().isEmpty && lines[i + 1].trim().isEmpty) {
      lines.removeAt(i + 1);
    }
  }
}
