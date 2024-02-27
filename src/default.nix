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

  mkHelmMultiTarget = { defaults ? _: { }, targets }:
    let
      chartConstructor = name: target:
        let
          args = (lib.recursiveUpdate (defaults args) (target args));
        in
        mkHelm args;
      deployments = lib.mapAttrs chartConstructor targets;
      mkAllScript = scriptKey:
        pkgs.writers.writeBashBin "all-${scriptKey}.sh"
          (lib.concatStringsSep "\n"
            (lib.mapAttrsToList
              (name: value: ''
                echo -e "\n\n\e[1m—————————————————————————————————————————————————————————\e[0m"
                echo -e "\e[1mExecuting ${scriptKey} on '\e[34m${name}\e[0m\e[1m':\e[0m\n"
                ${value.${scriptKey}}/bin/${value.${scriptKey}.meta.mainProgram}
              '')
              deployments));
    in
    deployments // {
      ALL = {
        apply = mkAllScript "apply";
        destroy = mkAllScript "destroy";
        plan = mkAllScript "plan";
        status = mkAllScript "status";
      };
    };
in
{
  inherit mkHelmMultiTarget mkHelm mkOutput;
}
