{
  trivial,
  root,
  super,
}:
/*
Use the Containers Blocktype for OCI-images built with nix2container.

Available actions:
  - print-image
  - publish
  - load
*/
let
  inherit (root) mkCommand actions;
  inherit (super) addSelectorFunctor;
  inherit (builtins) toFile;
in
  name: {
    __functor = addSelectorFunctor;
    inherit name;
    type = "containers";
    actions = {
      currentSystem,
      fragment,
      fragmentRelPath,
      target,
      inputs,
    }: let
      inherit (inputs.n2c.packages.${currentSystem}) skopeo-nix2container;
      triv = trivial.${currentSystem};
      inherit (builtins) unsafeDiscardStringContext;
      # The discover step (std-action's eval.sh) runs the proviso by its
      # store path WITHOUT realising it — see its comment "this trick
      # doesn't require proviso to be executable, as created by
      # builtins.toFile". So the proviso path must be materialised at
      # eval time. `toFile` does that (it's `addTextToStore`); a
      # `writeShellScript` derivation does NOT — its output only exists
      # once built, so discover would hit `No such file or directory` and
      # drop every publish action.
      #
      # `toFile` rejects strings carrying derivation context, so we can't
      # let it register skopeo/jq as build deps. We still pin them by
      # absolute store path (PR intent: no PATH dependency) AND guarantee
      # they're materialised before use:
      #
      #   - Discover's `nix eval` of the action list forces this proviso
      #     text, which forces `skopeo.drvPath` / `jq.drvPath` below —
      #     instantiating those .drv files into the local store as a side
      #     effect of evaluation (no build).
      #   - At runtime the proviso realises those .drv paths. Unlike
      #     realising a bare *output* path (which can only substitute),
      #     realising a locally-present .drv builds or substitutes
      #     reliably — so skopeo/jq are guaranteed present and the
      #     "already published? skip" check can't silently fail open.
      #
      # `unsafeDiscardStringContext` strips the context so `toFile`
      # accepts the interpolated paths; the forcing above already did its
      # job by the time the context is discarded.
      skopeoBin = unsafeDiscardStringContext "${skopeo-nix2container}/bin/skopeo";
      jqBin = unsafeDiscardStringContext "${triv.jq}/bin/jq";
      skopeoDrv = unsafeDiscardStringContext skopeo-nix2container.drvPath;
      jqDrv = unsafeDiscardStringContext triv.jq.drvPath;
      proviso = toFile "containers-proviso" ''
        # Ensure skopeo + jq are in the store (see the Nix comment above).
        # No-op when already present. Otherwise, because the .drv is local,
        # this substitutes from a cache if one has it and BUILDS FROM SOURCE
        # if none does — so the check never silently fails open on a host
        # without a pre-populated cache.
        nix-store --realise ${skopeoDrv} ${jqDrv} >/dev/null

        declare action="$1"
        declare image

        eval "$(${jqBin} -r '@sh "image=\(.meta.image)"' <<<"$action")"

        if ${skopeoBin} inspect --insecure-policy "docker://$image" &>/dev/null; then
          exit 1
        fi

        exit 0
      '';

      tags' =
        builtins.toFile "${target.name}-tags.json" (builtins.concatStringsSep "\n" target.image.tags);
      copyFn = ''
        copy() {
          local uri prev_tag
          uri=$1
          shift

          for tag in $(<${tags'}); do
            if ! [[ -v prev_tag ]]; then
              skopeo --insecure-policy copy nix:${target} "$uri:$tag" "$@"
            else
              # speedup: copy from the previous tag to avoid superflous network bandwidth
              skopeo --insecure-policy copy "$uri:$prev_tag" "$uri:$tag" "$@"
            fi
            echo "Done: $uri:$tag"

            prev_tag="$tag"
          done
        }
      '';
    in [
      (actions.build currentSystem target)
      (mkCommand currentSystem "print-image" "print out the image.repo with all tags" [] ''
        echo
        for tag in $(<${tags'}); do
          echo "${target.image.repo}:$tag"
        done
      '' {})
      (mkCommand currentSystem "publish" "copy the image to its remote registry" [skopeo-nix2container] ''
          ${copyFn}
          copy docker://${target.image.repo} "$@"
        '' {
          meta.image = target.image.name;
          inherit proviso;
        })
      (mkCommand currentSystem "load" "load image to the local docker daemon" [skopeo-nix2container] ''
        ${copyFn}
        if command -v podman &> /dev/null; then
           echo "Podman detected: copy to local podman"
           copy containers-storage:${target.image.repo} "$@"
        fi
        if command -v docker &> /dev/null; then
           echo "Docker detected: copy to local docker"
           copy docker-daemon:${target.image.repo} "$@"
        fi
      '' {})
    ];
  }
