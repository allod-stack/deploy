#!/usr/bin/env bash
#
# This repo's gate, in place of `nix flake check` (README.md, Check).
#
#     ./check.sh
#
# Runs the framework's own gate against this flake: the `check.sh` inside the
# `archetypes` revision `flake.lock` pins, so the gate and the checks it runs
# come from one revision and no live framework checkout is needed.

set -euo pipefail

if [ "$#" -gt 0 ]; then
  printf 'usage: %s\n' "$0" >&2
  exit 2
fi

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# The checkout path travels by environment variable, never spliced into the
# expression, so no character in it can be read as Nix.
framework="$(DEPLOY_GATE_FLAKE="$here" nix eval --raw --impure --expr \
  '(builtins.getFlake (builtins.getEnv "DEPLOY_GATE_FLAKE")).inputs.archetypes.outPath')" \
  || die "could not resolve the pinned archetypes source from $here"

[ -x "$framework/check.sh" ] \
  || die "the pinned archetypes revision carries no check.sh at $framework"

exec "$framework/check.sh" "$here"
