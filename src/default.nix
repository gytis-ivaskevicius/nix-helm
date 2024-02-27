{ pkgs
, lib
}:
let
  mkOutput = import ./mkOutput.nix { inherit pkgs lib; };

  mkHelm = { name, chart, namespace, context, kubeconfig, values, templates ? { }, kustomization ? { } }:
    let
      output = mkOutput { inherit name values chart templates namespace kubeconfig context kustomization; };
      mkAction = execName: {
        inherit (output) drvPath type outPath outputName name; meta.mainProgram = execName;
      };

      self = {
        inherit (output) drvPath type;
        apply = mkAction "apply.sh";
        destroy = mkAction "destroy.sh";
        plan = mkAction "plan.sh";
        status = mkAction "status.sh";
      };
    in
    self;

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
