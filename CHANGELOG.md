# Changelog

## Unreleased

### Added

- Initial boilerplate.
- Add git parameter to localize refs get
- Add commands to export
- Add tests for get ref and set ref
- Add get version command
- Add tests for process dependencies
- add .idea to .gitignore
- Add publish\_to: none when localizing
- Add .gitattributes file
- Add --git-ref option to localize-refs for custom git refs
- Add test for updating .gitignore with missing .gg entries
- Add tests for devDependencies handling in TS localize/unlocalize
- Add tests for dependency and manifest methods in language tests

### Changed

- Automatic checks
- Collect all nodes in allNodesMap
- posix style path
- change ggLog parameter to optional
- Use sample\_folder for test files
- Create backend subfolder and move source files
- changed gg\_local\_package\_dependencies to git dependency

### Fixed

- Fix tests on windows

### Removed

- Update gg\_publish to ^^3.2.0 and remove publish\_to field
