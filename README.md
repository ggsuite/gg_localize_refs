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
keeps a localized package publishable and keeps the local wiring in one file
that a single command writes and removes again.

`pubspec_overrides.yaml` **is committed**. It contains only relative paths, so a
shared ticket workspace resolves against the same sibling checkouts for everyone
— and pub always excludes it from a published package. `change-refs-to-local`
therefore removes a stale `pubspec_overrides.yaml` line from `.gitignore` if it
finds one, because a file that is gitignored *and* checked in makes
`dart pub publish` fail.

Leaving local mode removes the overrides this tool wrote — hand written entries
in that file survive.

pnpm-managed TypeScript/JavaScript projects get the same architecture:
`package.json` keeps its published constraints and the `link:` specs (or the
`git+…#ref` pins of git feature branch mode) go into the `overrides` section
of `pnpm-workspace.yaml` — pnpm's settings file, which pnpm reads for the
whole resolution and never ships with a published tarball. Like
`pubspec_overrides.yaml` it is committed and merged into: settings such as
`allowBuilds` and hand written overrides survive, and the file is deleted
again only when this tool created it.

npm's own top-level `overrides` field of `package.json` cannot express this:
npm refuses an override that conflicts with a direct dependency
(`EOVERRIDE`), and pnpm ignores that field entirely (pnpm ≥ 11 also ignores
`pnpm.overrides` inside `package.json`). A TypeScript project **not** managed
by pnpm therefore keeps the legacy behavior: its `link:` specs are written
into `package.json` directly, with the original specs backed up.

## Debugging across the TypeScript packages of a workspace

A `link:` straight to the sibling checkout redirects the *installed*
dependency, but the consumer still enters it through the `main`/`types` of
the sibling's `package.json` — its compiled `dist/`. That output is missing
in a fresh checkout, goes stale with every edit of the sibling and carries no
source map by default, so a test stepping into the dependency lands in
generated JavaScript and a breakpoint in the sibling's TypeScript is never
hit.

`change-refs-to-local` therefore links every pnpm dependency through a shim:

```
.gg/ts_links/@scope/dep/
├── package.json   {"name": "@scope/dep", "main": "./src/index.ts", "types": "./src/index.ts", …}
└── src -> /abs/path/to/ticket/dep/src
```

```yaml
# pnpm-workspace.yaml
overrides:
  "@scope/dep": link:./.gg/ts_links/@scope/dep
```

vitest, `tsc` and the editor all follow the link into the sibling's source:
edits are picked up immediately, stack traces name the `.ts` file,
breakpoints in the sibling hit. Nothing has to be configured in either repo.
The `src` symlink is what keeps TypeScript (which resolves `main`/`types`
relative to the path inside `node_modules`) and Vite (which resolves relative
to the real location) in agreement.

The shims are machine-local helper files below the gitignored `.gg/` and are
rewritten by every localizing run. Only a sibling with a `src/index.ts` gets
one; anything else keeps the plain `link:` to the sibling checkout.
`change-refs-to-pub-dev` and `change-refs-to-git-feature-branch` remove them.
