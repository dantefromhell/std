let
  inherit (inputs.cells.std.errors) requireInput;

  inherit (requireInput "devshell" "github:numtide/devshell" "std.lib.dev.mkShell") devshell nixago;

  l = inputs.nixpkgs.lib // builtins;

  pkgs = import inputs.nixpkgs {
    inherit (inputs.nixpkgs.stdenv.hostPlatform) system;
    overlays = [devshell.overlays.default];
  };
in
  configuration: let
    nixagoModule = {
      config,
      lib,
      ...
    }:
      with lib; let
        cfg = config;
      in {
        options.nixago = mkOption {
          type = types.listOf types.attrs;
          default = [];
          apply = x: l.catAttrs "__passthru" x;
          description = "List of `std` Nixago pebbles to load";
        };

        config = let
          # effectuate side effects on treefmt nixago, if present
          # to prevent treefmt from formatting auto-generated files
          partitioned = l.partition (n: n.output == "treefmt.toml") cfg.nixago;
          treefmt' =
            l.map (
              t:
                l.recursiveUpdate t
                {
                  data.global.excludes =
                    t.data.global.excludes
                    or []
                    ++ (l.map (o: o.output) cfg.nixago);
                }
            )
            # if there's more than one treefmt, that's a malconfiguration
            # but here: we don't deal with that case
            partitioned.right;
          updated = treefmt' ++ partitioned.wrong;
        in
          mkIf (cfg.nixago != []) {
            devshell = let
              acc = l.foldl l.recursiveUpdate {};
            in
              acc (
                []
                ++ (l.map (o: o.devshell) updated)
                ++ [{startup.nixago-setup-hook = l.stringsWithDeps.noDepEntry (nixago.lib.makeAll updated).shellHook;}]
              );
            packages = l.concatMap (o: o.packages) updated;
            commands = l.concatMap (o: o.commands) updated;
          };
      };
    # `nix develop` evaluates the derivation's outer shellHook *before*
    # devshell's env.bash is sourced (which is where PRJ_ROOT=$PWD happens, see
    # devshell's modules/devshell.nix). Prepending a `cd` to the real project
    # root here makes PRJ_ROOT correct, and makes nixago — whose hooks resolve
    # output paths against $PWD — materialize files at the project root rather
    # than wherever `nix develop` was invoked from. The trailing `cd` restores
    # the user's invocation cwd for the interactive shell.
    shell = pkgs.devshell.mkShell {
      imports = [configuration nixagoModule];
    };
    rootPrelude = ''
      _std_orig_pwd="$PWD"
      if _std_root="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null)"; then
        cd "$_std_root"
      else
        echo "std: not in a git repo; using \$PWD ($PWD) as project root" >&2
      fi
      unset _std_root
    '';
    rootEpilogue = ''
      cd "$_std_orig_pwd"
      unset _std_orig_pwd
    '';
  in
    derivation (shell.drvAttrs
      // {
        shellHook = rootPrelude + shell.drvAttrs.shellHook + rootEpilogue;
      })
