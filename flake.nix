{
  description = "Allod deploy template — the composition root machines are built from";

  # Deployment root: the flake you build to stand up your machines. It pins the
  # `archetypes` framework and the `profiles`/`secrets`/`inventory` data repos,
  # and redirects the framework's own `profiles`/`secrets`/`inventory` inputs at
  # these via `follows`. This public template points them at the allod/* synthetic
  # templates and builds the example fleet as-is; a fork changes exactly the three
  # data input URLs (`profiles`, `secrets`, `inventory`) and nothing else — the
  # "nothing else differs" charter, now enforceable by diff against this template.
  # Fork-private additions (extra checks, say) layer on top of this shape.
  inputs = {
    archetypes.url = "git+https://forge.anarch.diy/allod/archetypes.git";

    profiles.url  = "git+https://forge.anarch.diy/allod/profiles.git";
    secrets.url   = "git+https://forge.anarch.diy/allod/secrets.git";
    inventory.url = "git+https://forge.anarch.diy/allod/inventory.git";

    archetypes.inputs.profiles.follows  = "profiles";
    archetypes.inputs.secrets.follows   = "secrets";
    archetypes.inputs.inventory.follows = "inventory";

    # pkgs for the composed-layer canary only; follows the framework's nixpkgs so
    # this template pins no divergent nixpkgs.
    nixpkgs.follows = "archetypes/nixpkgs";
  };

  outputs = { self, nixpkgs, archetypes, profiles, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in {
      nixosConfigurations = archetypes.nixosConfigurations;

      # Host scripts (allod/nexus#6) resolve VM rebuild/provision facts from
      # DEPLOY_FLAKE#vmFacts; re-export the composed facts from archetypes.
      vmFacts = archetypes.vmFacts;

      # Generic composed-layer canary: fails loudly when the archetypes framework
      # composed a different profiles than this deploy flake pins — i.e. when the
      # `archetypes.inputs.profiles.follows = "profiles"` redirect above is lost or
      # dropped in a fork. Builds green here because the redirect is intact.
      checks = nixpkgs.lib.genAttrs systems (system: {
        composed-layer = archetypes.lib.composedLayerCheck {
          pkgs = nixpkgs.legacyPackages.${system};
          expectedProfiles = profiles;
        };
      });
    };
}
