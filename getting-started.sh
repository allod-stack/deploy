#!/usr/bin/env bash
# getting-started.sh - turn a fresh NixOS install into an Allod hypervisor
# that can provision its first dev VM, with no forge account and nothing to
# fetch but the public repos.
#
# On the machine, as the user you log in as (not root):
#
#   curl -O https://forge.anarch.diy/allod/deploy/raw/branch/master/getting-started.sh
#   bash getting-started.sh
#
# Then reboot, log in as the same user with the same password, and run
# `provision-vm allod-dev`.
#
# What it does, in order; every step is skipped when its result exists:
#   1. clones the public allod repos under ~/work/allod/, the layout the host
#      scripts resolve through the inventory's repository registry
#   2. copies this machine's /etc/nixos/hardware-configuration.nix over the
#      inventory's hypervisor hardware module
#   3. generates ~/.ssh/host, the hypervisor identity, and a fresh host key
#      for every VM, each encrypted to it; takes the dev VM out of forge
#      access and makes every one of its repos host-provided, so the VM is
#      built from these clones and no forge credential exists anywhere
#   4. points the deploy clone's three data inputs at the local clones
#   5. builds the installer image the VMs boot from, into ~/iso/
#   6. builds the hypervisor configuration and makes it the next boot
#
# The account that runs this stays the operator account: NixOS keeps mutable
# users, so its uid, password and home survive the switch. Only step 6 needs
# sudo, for the bootloader entry. Nothing here partitions, formats or
# reboots.
#
# Rerunnable. Clones that already exist are left as they are, a host key that
# exists is kept, VM keys are regenerated only once, and the build steps
# always run so a rerun after fixing something picks up the fix.
set -euo pipefail

FORGE_URL="${ALLOD_FORGE_URL:-https://forge.anarch.diy}"
WORK="${HOME}/work/allod"
HARDWARE_CONFIG="${ALLOD_HARDWARE_CONFIG:-/etc/nixos/hardware-configuration.nix}"
HOST_KEY="${HOME}/.ssh/host"
HYPERVISOR=nexus
DEV_VM=allod-dev
# All of them: the dev VM lists every one, and the host pushes its own clones.
REPOS=(deploy inventory secrets profiles archetypes nexus vm tools strategy memory)
DATA_INPUTS=(profiles secrets inventory)

export NIX_CONFIG="experimental-features = nix-command flakes"

die() { printf 'getting-started: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

# --- 0. preconditions --------------------------------------------------------

[[ "${1:-}" == "--prepare-only" ]] && PREPARE_ONLY=true || PREPARE_ONLY=false

[[ "$(id -u)" -ne 0 ]] \
  || die "run this as the user you will log in as, not as root"
[[ -e /etc/NIXOS ]] \
  || die "this is not a NixOS system"
[[ -r "$HARDWARE_CONFIG" ]] \
  || die "no hardware module at ${HARDWARE_CONFIG}; install NixOS first, or set ALLOD_HARDWARE_CONFIG"

if [[ -z "${ALLOD_GETTING_STARTED_SHELL:-}" ]]; then
  export ALLOD_GETTING_STARTED_SHELL=1
  printf 'Fetching git, age and jq...\n'
  exec nix-shell -p git age jq --run "bash $(printf '%q' "$0") $(printf '%q ' "$@")"
fi

for tool in git age jq ssh-keygen nix nixos-rebuild; do
  command -v "$tool" >/dev/null || die "missing tool: ${tool}"
done

git_commit() {
  local repo="$1"; shift
  git -C "$repo" add -A
  git -C "$repo" -c user.name="$USER" -c user.email="${USER}@${HOSTNAME:-nexus}" \
    commit -q -m "$@"
}

# --- 1. clone ----------------------------------------------------------------

step "Public repos under ${WORK}"
mkdir -p "$WORK"
for r in "${REPOS[@]}"; do
  if [[ -d "${WORK}/${r}/.git" ]]; then
    printf '  %-11s present\n' "$r"
  else
    printf '  %-11s cloning\n' "$r"
    git clone -q "${FORGE_URL}/allod/${r}.git" "${WORK}/${r}"
  fi
done

INVENTORY="${WORK}/inventory"
SECRETS="${WORK}/secrets"
DEPLOY="${WORK}/deploy"

# --- 2. hardware -------------------------------------------------------------

step "Hypervisor hardware from ${HARDWARE_CONFIG}"
HARDWARE_FILE="${INVENTORY}/hosts/${HYPERVISOR}/hardware.nix"
[[ -e "$HARDWARE_FILE" ]] \
  || die "the inventory clone has no ${HARDWARE_FILE#"${WORK}/"}; it predates the file split this script needs"
if cmp -s "$HARDWARE_CONFIG" "$HARDWARE_FILE"; then
  printf '  already in place\n'
else
  install -m 644 "$HARDWARE_CONFIG" "$HARDWARE_FILE"
  git_commit "$INVENTORY" "getting-started: this machine's hardware module"
  printf '  copied\n'
fi

# --- 3. identity -------------------------------------------------------------

step "Hypervisor identity ${HOST_KEY}"
if [[ -f "$HOST_KEY" ]]; then
  printf '  present\n'
else
  mkdir -p -m 700 "${HOME}/.ssh"
  ssh-keygen -q -t ed25519 -N "" -C "${HYPERVISOR}-host" -f "$HOST_KEY"
  printf '  generated\n'
fi
HOST_PUB_MATERIAL=$(cut -d' ' -f1,2 "${HOST_KEY}.pub")

if grep -q "hostPublicKey = \"${HOST_PUB_MATERIAL} " "${SECRETS}/identity.nix"; then
  printf '  secrets already keyed to it\n'
else
  # Each sed replaces one whole line whose shape the template fixes; the
  # eval at the end proves the result still parses.
  sed -i \
    -e "s|^  username = \".*\";|  username = \"${USER}\";|" \
    -e "s|^  hostPublicKey = \".*\";|  hostPublicKey = \"${HOST_PUB_MATERIAL} ${HYPERVISOR}\";|" \
    -e "s|^      forgeAccess = true;|      forgeAccess = false;|" \
    "${SECRETS}/identity.nix"
  grep -q "hostPublicKey = \"${HOST_PUB_MATERIAL} " "${SECRETS}/identity.nix" \
    || die "could not set hostPublicKey in ${SECRETS}/identity.nix"
  grep -q 'forgeAccess = false;' "${SECRETS}/identity.nix" \
    || die "could not clear forgeAccess in ${SECRETS}/identity.nix"

  # Private halves exist only on tmpfs for the length of this block.
  keydir=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/dev/shm}")
  trap 'rm -rf "$keydir"' EXIT
  (
    umask 077
    for vm in $(jq -r 'keys[]' "${SECRETS}/machine-host-keys.json"); do
      ssh-keygen -q -t ed25519 -N "" -C "$vm" -f "${keydir}/${vm}"
      rm -f "${SECRETS}/secrets/vm-host-keys/${vm}-ssh.age"
      age -R "${HOST_KEY}.pub" -o "${SECRETS}/secrets/vm-host-keys/${vm}-ssh.age" < "${keydir}/${vm}"
      jq --arg vm "$vm" --arg pub "$(cat "${keydir}/${vm}.pub")" \
        '.[$vm] = { active: $pub, staged: null }' \
        "${SECRETS}/machine-host-keys.json" > "${keydir}/keys.json"
      mv "${keydir}/keys.json" "${SECRETS}/machine-host-keys.json"
      printf '  %s host key regenerated\n' "$vm"
    done
    rm -f "${SECRETS}/secrets/vm-host-keys/${HYPERVISOR}-ssh.age"
    age -R "${HOST_KEY}.pub" -o "${SECRETS}/secrets/vm-host-keys/${HYPERVISOR}-ssh.age" < "$HOST_KEY"
  )
  rm -rf "$keydir"; trap - EXIT

  # Forge-less: no forge key, no agent token.
  printf '{}\n' > "${SECRETS}/forge-ssh-keys.json"
  rm -f "${SECRETS}/secrets/agent-pr-token.age" \
        "${SECRETS}/secrets/${DEV_VM}-forge-key.age" \
        "${SECRETS}/keys/"*.pub
  git_commit "$SECRETS" "getting-started: this deployment's identity, forge-less"
  printf '  secrets keyed\n'
fi

step "Guest addresses on libvirt's default network"
# The template uses documentation addresses; libvirt's default network, which
# new-vm reserves leases on, is 192.168.122.0/24.
sed -i -E 's/"192\.0\.2\.(2|10|11)"/"192.168.122.\1"/' "${INVENTORY}/flake.nix" "${SECRETS}/identity.nix"
if [[ -n "$(git -C "$INVENTORY" status --porcelain)$(git -C "$SECRETS" status --porcelain)" ]]; then
  git_commit "$INVENTORY" "getting-started: guests on libvirt's default network"
  git_commit "$SECRETS" "getting-started: guests on libvirt's default network"
  printf '  moved to 192.168.122.0/24\n'
else
  printf '  already there\n'
fi

step "Dev VM ${DEV_VM} built from the local clones, no forge key"
if grep -q 'host_provided_repos = \[ "allod/tools"' "${INVENTORY}/flake.nix"; then
  printf '  already declared\n'
else
  sed -i \
    -e "s|^\( *\)forge_key = \"allod_vm\";|\1forge_key = null;|" \
    -e "s|^\( *\)repos = \(\[ \"allod/tools\".*\];\)|\1repos = \2\n\1host_provided_repos = \2|" \
    "${INVENTORY}/flake.nix"
  grep -q 'host_provided_repos = \[ "allod/tools"' "${INVENTORY}/flake.nix" \
    || die "could not declare host_provided_repos in ${INVENTORY}/flake.nix"
  nix eval --raw "path:${INVENTORY}#lib.vmSpecsJson" | jq -S . > "${INVENTORY}/scripts/vm-specs.json"
  git_commit "$INVENTORY" "getting-started: ${DEV_VM} is host-provided and forge-less"
  printf '  declared\n'
fi

# --- 4. deploy inputs --------------------------------------------------------

step "Deploy inputs at the local clones"
for input in "${DATA_INPUTS[@]}"; do
  sed -i -E "s|^(    ${input}\.url += )\".*\";|\1\"git+file://${WORK}/${input}\";|" "${DEPLOY}/flake.nix"
  grep -q "${input}.url *= \"git+file://${WORK}/${input}\";" "${DEPLOY}/flake.nix" \
    || die "could not point the ${input} input at ${WORK}/${input}"
done
if [[ -n "$(git -C "$DEPLOY" status --porcelain)" ]]; then
  git_commit "$DEPLOY" "getting-started: data inputs at the local clones"
fi
(cd "$DEPLOY" && nix flake update "${DATA_INPUTS[@]}")
if [[ -n "$(git -C "$DEPLOY" status --porcelain)" ]]; then
  git_commit "$DEPLOY" "getting-started: lock the local clones"
fi
printf '  evaluating the hypervisor configuration...\n'
TOPLEVEL=$(cd "$DEPLOY" && nix eval --raw ".#nixosConfigurations.${HYPERVISOR}.config.system.build.toplevel.drvPath")
printf '  %s\n' "$TOPLEVEL"

if $PREPARE_ONLY; then
  printf '\n--prepare-only: stopping before the builds.\n'
  exit 0
fi

# --- 5. installer image ------------------------------------------------------

step "Installer image for the VMs, into ${HOME}/iso"
mkdir -p "${HOME}/iso"
nix build "${DEPLOY}#nixosConfigurations.installer.config.system.build.isoImage" \
  -o "${WORK}/.installer-image"
cp -f "${WORK}/.installer-image"/iso/*.iso "${HOME}/iso/nixos-minimal-allod-installer.iso"
printf '  %s\n' "${HOME}/iso/nixos-minimal-allod-installer.iso"

# --- 6. hypervisor -----------------------------------------------------------

step "Hypervisor configuration as the next boot (sudo for the bootloader)"
nixos-rebuild boot --flake "${DEPLOY}#${HYPERVISOR}" --sudo

cat <<EOF

Done. Next:

  1. reboot
  2. log in as ${USER}, with the same password
  3. provision-vm ${DEV_VM}
  4. ssh ${DEV_VM}

Your deployment is the four clones under ${WORK}: inventory, secrets,
profiles and deploy. Commit there, rebuild with
  nixos-rebuild switch --flake ${DEPLOY}#${HYPERVISOR} --sudo
and push the clones to a forge of your own whenever you want one.
EOF
