# deploy

Deploy-flake template — the composition root you build machines from, and the
flake host provisioning consumes via `DEPLOY_FLAKE` (it resolves VM
rebuild/provision facts from `DEPLOY_FLAKE#vmFacts`).

It composes the reusable public Allod config (`allod/profiles`, which pulls in
`allod/nexus` and `allod/vm`) and redirects profiles' `secrets` and
`inventory` inputs at data repos via `follows`. This template points both at
the `allod/*` synthetic templates, so it evaluates the example fleet as-is; a
fork points those two inputs at its own repos to build real machines. Nothing
else differs.

## Build

```
nixos-rebuild switch --flake .#<machine> --target-host <user>@<ip> --sudo
```

`flake.lock` pins exact `secrets`, `inventory`, and `profiles` revisions, so
the build and the host-key preflight agree on one source of truth.

## Fork

1. Fork this repo.
2. Point `secrets.url` and `inventory.url` at your own repos.
3. `nix flake update secrets inventory` and commit the lock.

Fork-private additions (extra `checks`, for example) layer on top of this
shape; keep the input redirection the only difference in the template files so
re-syncs against the template stay reviewable.
