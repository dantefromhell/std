# SPDX-FileCopyrightText: 2022 The Standard Authors
# SPDX-FileCopyrightText: 2022 Kevin Amado <kamadorueda@gmail.com>
#
# SPDX-License-Identifier: Unlicense
{
  description = "The Nix Flakes framework for perfectionists with deadlines";
  # 2026-02-26 @mayeu: I don't understand what it is, and why it's there
  # but it doesn't work for me:
  #
  #     ➜ nix --version
  #     ➜ direnv allow
  #     error: flake 'self' attribute 'shallow' is not supported
  #     direnv: The follwing command just failed:
  #     direnv: nix build --no-update-lock-file --no-write-lock-file --no-warn-dirty --accept-flake-config --no-link --keep-outputs --build-poll-interval 0 --builders-use-substitutes --print-out-paths --profile /Users/m/code-des-autres/std/.data/local/shells/default/enter-action git+file:///Users/m/code-des-autres/std#__std.actions.aarch64-darwin.local.shells.default.enter
  #     Rerun with --show-trace (y/N): y
  #     error: flake 'self' attribute 'shallow' is not supported.
  #
  #inputs.self.shallow = true;
  # override downstream with inputs.std.inputs.nixpkgs.follows = ...
  inputs.nixpkgs.url = "github:nixos/nixpkgs/release-25.11";
  inputs.lib.url = "github:nix-community/nixpkgs.lib";
  inputs = {
    paisano.url = "github:paisano-nix/core/0.2.0";
    paisano.inputs.nixpkgs.follows = "nixpkgs";
    paisano.inputs.yants.follows = "yants";
    paisano-tui = {
      url = "github:paisano-nix/tui/v0.5.0";
      flake = false; # we're after the source code, only
    };
  };
  inputs.blank.url = "github:divnix/blank";
  inputs.yants = {
    url = "github:divnix/yants";
    inputs.nixpkgs.follows = "lib";
  };
  inputs.dmerge = {
    url = "github:divnix/dmerge/0.2.1";
    inputs.haumea.follows = "haumea";
    inputs.yants.follows = "yants";
    inputs.nixlib.follows = "lib";
  };
  inputs.haumea = {
    url = "github:nix-community/haumea/v0.2.2";
    inputs.nixpkgs.follows = "lib";
  };
  inputs.incl = {
    url = "github:divnix/incl";
    inputs.nixlib.follows = "lib";
  };
  /*
  Auxiliar inputs used in builtin libraries or for the dev environment.
  */
  inputs = {
    # Placeholder inputs that can be overloaded via follows
    n2c.follows = "blank";
    devshell.follows = "blank";
    nixago.follows = "blank";
    terranix.follows = "blank";
    microvm.follows = "blank";
    makes.follows = "blank";
    arion.follows = "blank";
  };

  outputs = inputs: let
    # nixpkgs-unstable dropped x86_64-darwin from `lib.systems.doubles`. Paisano
    # validates a grow call's `systems` argument against a yants enum built from
    # `lib.systems.doubles.all` of the followed nixpkgs, and its built-in default
    # still lists x86_64-darwin, so any grow call that omits `systems` fails to
    # evaluate on the newer nixpkgs. We take paisano's historical default list
    # and keep only the systems the followed nixpkgs actually supports, so the
    # list adapts automatically to whatever nixpkgs is in use.
    supportedSystems =
      builtins.filter
      (s: builtins.elem s inputs.nixpkgs.lib.systems.doubles.all)
      ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    # bootstrap std
    fwlib = import ./src/std/fwlib.nix {
      inputs = inputs // {nixpkgs = inputs.nixpkgs.legacyPackages;};
      cell = {};
    };
    # load fwlib again through the framework
    # to enable input overloading for blocktypes
    fwlib' = inputs.paisano.pick (fwlib.grow {
      inherit inputs;
      systems = supportedSystems;
      cellsFrom = inputs.incl ./src ["std"];
      cellBlocks = [(fwlib.blockTypes.functions "fwlib")];
    }) ["std" "fwlib"];

    std = {
      # the framework's basic top-level tools
      inherit (inputs) yants dmerge incl;
      inherit (inputs.paisano) pick harvest winnow;
      inherit (fwlib') blockTypes actions dataWith flakeModule grow growOn findTargets;
    };
  in
    assert inputs.nixpkgs.lib.assertMsg (((builtins.compareVersions builtins.nixVersion "2.18.0-lix") >= 0) || ((builtins.compareVersions builtins.nixVersion "2.23") >= 0)) "The truth is: you'll need a newer version of nix (min. v2.23) or lix (min. 2.18) to use Standard.";
      (import ./dogfood.nix (inputs
        // {
          std = std // {inherit (inputs.self) narHash;};
        }))
      std;
}
