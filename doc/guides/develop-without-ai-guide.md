<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Develop without AI

## Prepare everything

If you have not done that yet:

[Install the required software](./install-guide.md)

[Initialize a gg workspace](./install-guide/install-gg-workspace-guide.md)

## Switch into your workspace

```bash
cd ~/dev/
```

## Add repos to the ticket

```bash
gg do add repo1 repo2
```

Name all repos in one call: every call refreshes the ocean and builds
the dependency graph again.

## Open the workspace in Vscode

```bash
gg do code
```

## Implement

Implement your features based on the guides

## Commit

```bash
gg do commit
```

## Push

```bash
gg do push
```

## Review

```bash
gg do review
```

## Publish

Publish from the workspace root and name the ticket with `-i`:

```bash
cd ~/dev/
gg do publish -i <ticket>
```

At the end gg moves the ticket folder to the trash. On Windows this fails
while a terminal sits in the ticket folder ("used by another process").
