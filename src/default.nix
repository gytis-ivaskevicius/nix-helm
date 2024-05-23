{ pkgs
, lib
}:
let
  mkOutput = import ./mkOutput.nix { inherit pkgs lib; };

  mkHelm = attrs:
    let
      eval = lib.evalModules {
        modules = [
          ./options.nix
          attrs
        ];
        specialArgs = { inherit pkgs; };
      };
    in
    eval.config.drv;

  mkHelmMultiTarget = { defaults ? _: { }, targets, targetGroups ? _: { } }:
    let
      chartConstructor = name: target:
        let
          args = (lib.recursiveUpdate (defaults args) (target args));
        in
        mkHelm args;

      deployments = lib.mapAttrs chartConstructor targets;
      mkAllScript = targets: scriptKey:
        pkgs.writers.writeBashBin "all-${scriptKey}.sh"
          (lib.concatStringsSep "\n"
            (lib.mapAttrsToList
              (name: value: ''
                echo -e "\n\n\e[1m—————————————————————————————————————————————————————————\e[0m"
                echo -e "\e[1mExecuting ${scriptKey} on '\e[34m${name}\e[0m\e[1m':\e[0m\n"
                ${value.${scriptKey}}/bin/${value.${scriptKey}.meta.mainProgram}
              '')
              (lib.mapAttrs chartConstructor targets)));
      targetGroups' = (targetGroups targets) // {
        ALL = targets;
      };
    in
    deployments // (lib.mapAttrs
      (name: targets: {
        apply = mkAllScript targets "apply";
        destroy = mkAllScript targets "destroy";
        plan = mkAllScript targets "plan";
        status = mkAllScript targets "status";
      })
      targetGroups');
in
{
  inherit mkHelmMultiTarget mkHelm mkOutput;
}
