# deploy

Deploy-flake template — the composition root you build machines from, and the
flake host provisioning consumes via `DEPLOY_FLAKE` (it resolves VM
rebuild/provision facts from `DEPLOY_FLAKE#vmFacts`).

It pins the `allod/archetypes` framework (which pulls in `allod/nexus` and
`allod/vm`) and the three data repos — `allod/profiles` (machine profile
definitions), `allod/secrets` (identity), and `allod/inventory` (machine facts)
— and redirects the framework's own `profiles`/`secrets`/`inventory` inputs at
them via `follows`. This template points all three at the `allod/*` synthetic
templates, so it evaluates the example fleet as-is; a fork points them at its
own repos to build real machines. Nothing else differs.

## Build

```
nixos-rebuild switch --flake .#<machine> --target-host <user>@<ip> --sudo
```

`flake.lock` pins exact `archetypes`, `profiles`, `secrets`, and `inventory`
revisions, so the build and the host-key preflight agree on one source of truth.

## Check

```
./check.sh
```

`./check.sh` replaces `nix flake check` for this repo. The native command
evaluates every machine and every check in one process, and a fork with a real
fleet is OOM-killed on an 8 GiB dev VM before it reaches the end of the check
list. The script runs the framework's gate from the `archetypes` revision
`flake.lock` pins: one `nix` process per machine and per check, every check
built rather than only evaluated, and one run reports every failing step.

It takes no arguments. To prove an unmerged data-repo branch, force the checks
that read it one at a time with
`nix build .#checks.<system>.<name> --override-input <input> <worktree> --no-write-lock-file`.

## Fork

1. Fork this repo.
2. Point `profiles.url`, `secrets.url`, and `inventory.url` at your own repos —
   **exactly these three input URLs and nothing else.** That is the whole
   difference between a fork and this template, enforceable by diff.
3. `nix flake update profiles secrets inventory` and commit the lock.

The framework repos `vm` and `nexus` are not redirected; they arrive through
`archetypes`' own lock and move with `nix flake update archetypes`. Fork-private
additions (extra `checks`, for example) layer on top of this shape; keep the
input redirection the only difference in the template files so re-syncs against
the template stay reviewable.

## Composed-layer canary

`checks.<system>.composed-layer` fails loudly if the `archetypes` framework
composed a different `profiles` than this flake pins — i.e. if the
`archetypes.inputs.profiles.follows = "profiles"` redirect is ever lost or
dropped in a fork (so machines would silently build from the wrong, public
example definitions). `nix flake check` runs it. `tests/empty-profiles` is a
minimal empty-contract profiles fixture the sabotage tests use to prove the
canary fires (see the M3 acceptance tests in the split plan).
