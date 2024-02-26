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
    in
    lib.mapAttrs chartConstructor targets;
in
{
  inherit mkHelmMultiTarget mkHelm mkOutput;
}
