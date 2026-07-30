# gg_localize_refs

gg_localize_refs allows to switch a local package and its local checkouts to local pathes

# Installation

`dart pub global activate --source path .`

# How localization works

A package can reference its local sibling checkouts in one of three mutually
exclusive modes. Exactly one is active at a time — switching modes always cleans
up after the previous one.

| Mode | Command | Where the refs live |
| --- | --- | --- |
| local | `change-refs-to-local` | `dependency_overrides` in `pubspec_overrides.yaml` |
| git feature branch | `change-refs-to-git-feature-branch --git-ref <ref>` | git refs in `pubspec.yaml` |
| pub.dev | `change-refs-to-pub-dev` | version constraints in `pubspec.yaml` |

For Dart packages, local mode does **not** modify `pubspec.yaml`: the published
version constraints stay in place and the local paths go into
`pubspec_overrides.yaml`, a file pub reads in addition to the manifest. That
keeps a localized package publishable, keeps developer-machine paths out of the
manifest, and makes the local wiring a one-file, throw-away artifact.

`pubspec_overrides.yaml` is local state and must never be committed:
`change-refs-to-local` adds it to `.gitignore` automatically. Leaving local mode
removes the overrides it wrote — hand written entries in that file survive.

TypeScript/JavaScript projects have no equivalent file, so their `link:` specs
are written into `package.json` as before.