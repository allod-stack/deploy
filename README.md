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

The forge is the source of truth; GitHub mirrors it at
[github.com/allod-stack](https://github.com/allod-stack), which also serves
the script:

```
curl -O https://raw.githubusercontent.com/allod-stack/deploy/master/getting-started.sh
ALLOD_SOURCE=github bash getting-started.sh
```

`ALLOD_SOURCE` picks where the public repos come from, clones and flake inputs
alike: `forge` (default), `github`, or an absolute directory holding the repos
on local disk, as checkouts (`<dir>/<repo>`, a copy of `~/work/allod`) or bare
mirrors (`<dir>/<repo>.git`), for a machine with no network to either. A
checkout is read at its current `HEAD`, so a dirty or branched copy is what
gets built. It is one git `insteadOf` rule in `~/.gitconfig`; the flake
lock keeps its forge URLs and nothing relocks. Rerun with `ALLOD_SOURCE=forge`
to route back.

It clones the public repos under `~/work/allod/`, uses this machine's own
`/etc/nixos/hardware-configuration.nix` as the hypervisor hardware, generates
the host identity and fresh VM host keys, takes the dev VM out of forge access
with every repo host-provided, points this flake's three data inputs at the
local clones, builds the installer image, and makes the hypervisor the next
boot. The header of the script lists each step. Then reboot, log in as the
same user, and `provision-vm allod-dev`. Firmware must be UEFI with Secure
Boot off; the stock installer already required that.

### Giving the agent a model

Inside the VM, once:

```
pi-key
```

It asks for a provider and lists the endpoint's models. nullsink
(https://nullsink.is) is pay per use with no account: buy a key with a few
dollars of credit first, pick it, paste the key at the hidden prompt. `pi-key`
checks the key against the endpoint and ends with `Run: pi`; then `pi` talks
to the model and `allod skill` lists what the agent knows how to do. A Claude
or ChatGPT subscription works too: run `claude` or `codex` in the VM, open the
URL it prints in the host's browser, and paste the code back.

To hand the key over from the host instead of typing it into the VM, save it
as a file there and pipe it in:

```
ssh allod-dev pi-key nullsink < ~/nullsink-key
```

It picks the first model the endpoint lists; add `--model <id>` to choose.
Either way the VM now holds a key file, `~/.pi/keys/nullsink`, and loses it
when the VM is replaced.

The durable way is the managed path: the key is pasted once on the host,
encrypted to the host's key and the VM's, and the VM uses it without ever
holding it. Rotation is then one command. On the host, once, so git knows
who you are:

```
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Then, still on the host (the prompt says `nexus`, not `allod-dev`):

```
mkdir -p ~/work/allod/secrets/secrets/pi-credentials
U=https://nullsink.is/v1
M=glm-5-3-flash
pi-provider add nullsink --credential nullsink --url $U --target allod-dev --model $M
git -C ~/work/allod/profiles commit -am "pi-providers: add nullsink"
git -C ~/work/allod/secrets add -A
git -C ~/work/allod/secrets commit -m "add nullsink token"
cd ~/work/allod/deploy
nix flake update --refresh profiles secrets
jq -r '.nodes.profiles.locked.rev, .nodes.secrets.locked.rev' flake.lock
git commit -am "lock: nullsink"
rebuild-vm allod-dev
```

The `pi-provider` line asks for the key, hidden. The `mkdir` is needed only
on a deployment that has never held a Pi credential (allod/nexus#80). Stop if
the `jq` line prints the same two revisions as before: the re-lock silently
did nothing, which happens when either clone had uncommitted changes. Then
inside the VM, `pi auth check --provider nullsink` says `ready`, `pi` answers,
and `~/.pi/keys` is empty. To rotate the key later, run
`pi-provider token rotate nullsink default` on the host and repeat the two
commits, the re-lock and the rebuild.

### Giving the dev VM its own forge

Three commands turn a forge-less dev VM into one with its own forge:

```
provision-vm forge
bash ~/work/allod/deploy/getting-started.sh --forge
ssh allod-dev
```

The second command runs `forge-sync forge` itself (prompting if it needs to)
and commits what it wrote, moves the forge host identity onto the forge VM's
own address, gives the dev VM its forge key back, re-locks the three data
inputs, checks the dev VM for work not yet received to the host, and
replaces it with `provision-vm --replace allod-dev` — the VM is replaced
rather than rebuilt in place, because its clones were pulled from the host
and have no remote. It ends by printing the forge login.

Safe to rerun: once allod-dev already clones from the forge, the run checks
for that first and replaces nothing — the guard and the replace both skip,
and only the login is printed again.

Because the replace discards the VM, anything done in the forge-less VM must
come back to the host first: `allod patch receive allod-dev:<repo> <repo>`
for every repo with work not yet on the host. The `--forge` run checks this
itself and refuses to replace the VM until it is done, printing the exact
command for each repo that still needs it.

### If it goes wrong

- Check the prompt first. Host commands run where it says `nexus`; VM
  commands where it says `allod-dev`. Most wrong turns are the right command
  on the wrong machine.
- Inside the VM, start `claude` (log in through the host's browser) and tell
  it the symptom. It can read the VM's journal and files itself and will hand
  you any host-side line to type.
- The script stops at the first failure and says which step. Rerunning it is
  safe; finished steps are skipped.
- After the reboot, if your login does not work, log in as `root` with the
  administrator password from the install and run `passwd <your user>`.
- `provision-vm` can fail on a slow download with `unexpected end-of-file`;
  run it again.
- Virtual Machine Manager opens empty: launch it as
  `virt-manager -c qemu:///system`, or add the QEMU/KVM system connection
  under File, Add Connection.

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
