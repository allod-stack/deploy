{
  description = "Empty profiles contract fixture — for the deploy composed-layer sabotage tests";

  # Exports the profiles input contract with no machine definitions. Used by the
  # M3 sabotage tests via --override-input:
  #  - overriding ONLY archetypes/profiles here makes the composed-layer canary
  #    fire (archetypes composes this empty fixture while the deploy pins the real
  #    profiles — a lost/dropped follows redirect); and
  #  - overriding BOTH profiles and archetypes/profiles here keeps the canary green
  #    (both point here) but makes machine eval throw "selects missing … profile
  #    definition", since no archetype declares any machine.
  outputs = { self, ... }: {
    lib = {
      profileDefinitions = { };
      profileData = { };
    };
    homeModules.preferences = { ... }: { };
  };
}
