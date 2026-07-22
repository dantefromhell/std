inputs: let
  inherit (inputs) incl std;
  inherit (inputs.paisano) pick harvest;
  # nixpkgs-unstable dropped x86_64-darwin from `lib.systems.doubles`. Paisano
  # validates a grow call's `systems` argument against a yants enum built from
  # `lib.systems.doubles.all` of the followed nixpkgs, and its built-in default
  # still lists x86_64-darwin, so any grow call that omits `systems` fails to
  # evaluate on the newer nixpkgs. We take paisano's historical default list and
  # keep only the systems the followed nixpkgs actually supports, so the list
  # adapts automatically to whatever nixpkgs is in use.
  supportedSystems =
    builtins.filter
    (s: builtins.elem s inputs.nixpkgs.lib.systems.doubles.all)
    ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
in
  std.growOn {
    inherit inputs;
    systems = supportedSystems;
    cellsFrom = incl ./src ["local" "tests"];
    nixpkgsConfig = {allowUnfree = true;};
    cellBlocks = with std.blockTypes; [
      ## For local use in the Standard repository
      # local
      (devshells "shells" {ci.build = true;})
      (nixago "configs")
      (containers "containers")
      (namaka "checks" {ci.check = true;})
    ];
  }
  {
    devShells = harvest inputs.self ["local" "shells"];
    checks = harvest inputs.self ["tests" "checks" "snapshots" "check"];
  }
  (std.grow {
    inherit inputs;
    systems = supportedSystems;
    cellsFrom = incl ./src ["std" "lib" "data"];
    cellBlocks = with std.blockTypes; [
      ## For downstream use

      # std
      (runnables "cli" {ci.build = true;})
      (functions "devshellProfiles")
      (functions "errors")
      (data "templates")

      # lib
      (functions "dev")
      (functions "ops")
      (anything "cfg")
      (data "configs")
    ];
  })
  {
    packages = harvest inputs.self [["std" "cli"] ["std" "packages"]];
    templates = pick inputs.self ["std" "templates"];
  }
