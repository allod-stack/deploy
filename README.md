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

## Getting started

From a fresh NixOS install to a hypervisor with one dev VM, no forge
account needed. On the machine, as the user you log in as:

```
curl -O https://forge.anarch.diy/allod/deploy/raw/branch/master/getting-started.sh
bash getting-started.sh
```

It clones the public repos under `~/work/allod/`, uses this machine's own
`/etc/nixos/hardware-configuration.nix` as the hypervisor hardware, generates
the host identity and fresh VM host keys, takes the dev VM out of forge access
with every repo host-provided, points this flake's three data inputs at the
local clones, builds the installer image, and makes the hypervisor the next
boot. The header of the script lists each step. Then reboot, log in as the
same user, and `provision-vm allod-dev`. Firmware must be UEFI with Secure
Boot off; the stock installer already required that.

## Build

```
nixos-rebuild switch --flake .#<machine> --target-host <user>@<ip> --sudo
```

`flake.lock` pins exact `archetypes`, `profiles`, `secrets`, and `inventory`
revisions, so the build and the host-key preflight agree on one source of truth.

## Check

```
allod check
```

`allod check` replaces `nix flake check` for this repo, because the native
command evaluates every machine and every check in one process and a fork with a
real fleet is OOM-killed on an 8 GiB dev VM before it reaches the end of the
check list. To run the whole gate against a data-repo branch before it merges:

```
allod check --override-input <input> <worktree>
```

See `docs/allod-check.md` in `allod/tools` for the rest.

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
