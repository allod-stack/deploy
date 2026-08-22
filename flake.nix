{
  description = "Allod deploy template — the composition root machines are built from";

  # Deployment root: the flake you build to stand up your machines. It pins the
  # `archetypes` framework and the `profiles`/`secrets`/`inventory` data repos,
  # and redirects the framework's own `profiles`/`secrets`/`inventory` inputs and
  # the secrets registry's inventory input at these via `follows`. This public
  # template points them at the allod/* synthetic
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
    secrets.inputs.inventory.follows    = "inventory";

    # pkgs for the composed-layer canary only; follows the framework's nixpkgs so
    # this template pins no divergent nixpkgs.
    nixpkgs.follows = "archetypes/nixpkgs";
  };

  outputs = { self, nixpkgs, archetypes, profiles, secrets, inventory, ... }:
    let
      # Derive the checked systems from the inventory source of truth rather than
      # hard-coding architecture strings.
      systems = inventory.lib.supportedPlatforms;
      expectedSources = {
        expectedProfiles = profiles;
        expectedSecrets = secrets;
        expectedInventory = inventory;
      };
      sabotageObservedSource = observation:
        !(builtins.tryEval (archetypes.lib.validateComposedLayerSources
          (expectedSources // { "${observation}" = "/sabotaged-${observation}"; }))).success;
      followsSabotage = {
        profiles = sabotageObservedSource "observedProfiles";
        secrets = sabotageObservedSource "observedSecrets";
        inventory = sabotageObservedSource "observedInventory";
        secretsInventory = sabotageObservedSource "observedSecretsInventory";
      };
      ineffectiveSabotage = builtins.attrNames
        (nixpkgs.lib.filterAttrs (_: failed: !failed) followsSabotage);
    in {
      nixosConfigurations = archetypes.nixosConfigurations;

      # Host scripts (allod/nexus#6) resolve VM rebuild/provision facts from
      # DEPLOY_FLAKE#vmFacts; re-export the composed facts from archetypes.
      vmFacts = archetypes.vmFacts;

      # Generic composed-layer canary: compares every consumed data source with
      # this deployment's pins. The four pure sabotage calls above replace one
      # observation at a time and must each trip the same validator used here.
      checks = nixpkgs.lib.genAttrs systems (system: {
        composed-layer =
          let
            emptyPiCredentialProjections = nixpkgs.lib.mapAttrs (_: _: {
              credentials = {};
              providers = {};
            }) secrets.lib.identity.devVMs;
            fixtureRegistry = {
              shared = {
                targets = [ "dev-a" "dev-b" ];
                providers = [ "alpha" "beta" ];
                tokens = [ "primary" "secondary" ];
                defaultToken = "primary";
              };
              solo = {
                targets = [ "dev-b" ];
                providers = [ "gamma" ];
                tokens = [ "only" ];
                defaultToken = null;
              };
            };
            fixtureKeys = {
              nexus = { active = "nexus-active"; staged = "nexus-staged"; };
              dev-a = { active = "dev-a-active"; staged = null; };
              dev-b = { active = "dev-b-active"; staged = "dev-b-staged"; };
            };
            fixtureArgs = {
              registry = fixtureRegistry;
              machines = {
                dev-a = { type = "dev"; runtime = "libvirt"; };
                dev-b = { type = "dev"; runtime = "libvirt"; };
                nexus = { type = "hypervisor"; };
              };
              devVMs = {
                dev-a = {};
                dev-b = {};
              };
              machineHostKeys = fixtureKeys;
              nexusName = "nexus";
              ciphertextRoot = "/synthetic-secrets";
              ciphertextExists = _: true;
            };
            fixtureWithoutDeclared = secrets.lib.mkPiCredentialContract fixtureArgs;
            fixture = secrets.lib.mkPiCredentialContract (fixtureArgs // {
              declaredRecipients = fixtureWithoutDeclared.recipients;
            });
            rejects = args:
              !(builtins.tryEval
                (builtins.deepSeq (secrets.lib.mkPiCredentialContract args) true)).success;
            sharedProjection = {
              providers = [ "alpha" "beta" ];
              tokens = {
                primary.file = "/synthetic-secrets/pi-credentials/shared/primary.age";
                secondary.file = "/synthetic-secrets/pi-credentials/shared/secondary.age";
              };
              defaultToken = "primary";
            };
            expectedProviderJoin = {
              alpha = "shared";
              beta = "shared";
              gamma = "solo";
            };
            expectedProjections = {
              dev-a = {
                credentials.shared = sharedProjection;
                providers = {
                  alpha = "shared";
                  beta = "shared";
                };
              };
              dev-b = {
                credentials = {
                  shared = sharedProjection;
                  solo = {
                    providers = [ "gamma" ];
                    tokens.only.file = "/synthetic-secrets/pi-credentials/solo/only.age";
                    defaultToken = null;
                  };
                };
                providers = expectedProviderJoin;
              };
            };
            defaultSabotage = fixtureArgs // {
              registry.shared = fixtureRegistry.shared // { defaultToken = "absent"; };
            };
          in
          assert nixpkgs.lib.assertMsg (ineffectiveSabotage == [])
            "composed-layer sabotage did not reject: ${nixpkgs.lib.concatStringsSep ", " ineffectiveSabotage}";
          assert nixpkgs.lib.assertMsg (secrets.lib.piCredentials == {})
            "composed-layer: public Pi credential registry is not empty";
          assert nixpkgs.lib.assertMsg (secrets.lib.piCredentialProjections == emptyPiCredentialProjections)
            "composed-layer: empty public Pi credential projections drifted";
          assert nixpkgs.lib.assertMsg (fixture.providerCredentials == expectedProviderJoin)
            "composed-layer: Pi provider-to-credential join drifted";
          assert nixpkgs.lib.assertMsg (fixture.projections == expectedProjections)
            "composed-layer: Pi per-target credential projections drifted";
          assert nixpkgs.lib.assertMsg (rejects defaultSabotage)
            "composed-layer: invalid Pi token default sabotage was accepted";
          archetypes.lib.composedLayerCheck ({
            pkgs = nixpkgs.legacyPackages.${system};
          } // expectedSources);
      });
    };
}
