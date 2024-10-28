/// Replaces the old with a new dependency in the pubspec.yaml file.
String replaceDependency(
  String yamlString,
  String depName,
  String oldDep,
  String newDep,
) {
  String oldDependencyPattern = r'\s+' +
      RegExp.escape('$depName: $oldDep').replaceAll(RegExp(r'\s+'), r'\s*') +
      r'\s*(#([\s\S]*?)\n\s*)?';
  RegExp oldDependencyRegex = RegExp(oldDependencyPattern);

  String regexMatch = oldDependencyRegex.firstMatch(yamlString)?.group(0) ?? '';
  String charsBeforeLastChar = RegExp(
        r'\s+' +
            RegExp.escape('$depName: $oldDep')
                .replaceAll(RegExp(r'\s+'), r'\s*') +
            r'[ \t]*(#([\s\S]*?))?\n',
      ).firstMatch(regexMatch)?.group(0) ??
      '';
  String charsAfterLastChar = !regexMatch.contains(charsBeforeLastChar)
      ? ''
      : regexMatch.substring(
          regexMatch.indexOf(charsBeforeLastChar) + charsBeforeLastChar.length,
        );

  if (newDep.contains('\n') || newDep.contains(RegExp.escape(':'))) {
    return yamlString.replaceAll(
      oldDependencyRegex,
      '\n  $depName: \n    $newDep\n$charsAfterLastChar',
    );
  }

  return yamlString.replaceAll(
    oldDependencyRegex,
    '\n  $depName: $newDep\n$charsAfterLastChar',
  );
}
