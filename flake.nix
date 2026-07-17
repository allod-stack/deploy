{
  description = "Allod deploy template — the composition root machines are built from";

  # Deployment root: the flake you build to stand up your machines. It takes
  # the reusable upstream config (profiles, which itself pulls nexus/vm) and
  # redirects profiles' `secrets` and `inventory` inputs at your own data
  # repos via `follows`. This public template points both at the allod/*
  # synthetic templates and builds the example fleet as-is; a fork points
  # them at its own repos and builds real machines. Nothing else differs —
  # fork-private additions (extra checks, say) layer on top of this shape.
  inputs = {
    profiles.url = "git+https://forge.anarch.diy/allod/profiles.git";

    secrets.url   = "git+https://forge.anarch.diy/allod/secrets.git";
    inventory.url = "git+https://forge.anarch.diy/allod/inventory.git";

    profiles.inputs.secrets.follows   = "secrets";
    profiles.inputs.inventory.follows = "inventory";
  };

  outputs = { profiles, ... }: {
    nixosConfigurations = profiles.nixosConfigurations;

    # Host scripts (allod/nexus#6) resolve VM rebuild/provision facts from
    # DEPLOY_FLAKE#vmFacts; re-export the composed facts from profiles.
    vmFacts = profiles.vmFacts;
  };
}
