{ pkgs, lib, config, ... }:
let
  inherit (lib) types literalExpression mkOption;
in
{
  options = {
    name = mkOption {
      description = "Name of Helm deployment";
      example = "my-helm-deployment-name";
      type = types.str;
    };

    namespace = mkOption {
      description = "Namespace where chart should be deployed";
      example = "default";
      type = types.str;
    };

    kubeconfig = mkOption {
      description = "Path to $KUBECONFIG. May contain variables like devshell provided $PRJ_ROOT";
      example = "$PRJ_ROOT/.kube/us-east-1";
      type = types.str;
    };

    context = mkOption {
      description = "KUBECONFIG context to use";
      example = "admin";
      type = types.str;
    };

    chart = mkOption {
      description = "Path to helm Chart.yaml";
      example = literalExpression "./Chart.yaml";
      type = types.path;
    };

    helmArgs = mkOption {
      description = "Arguments passed to helm";
      example = [ "--debug" ];
      default = [ ];
      type = types.listOf (types.either types.str types.path);
    };

    templates = mkOption {
      description = "Attrset of Kubernetes resources";
      example = literalExpression ''
        {
          resource-1 = ./path/to/template.yaml;
          resource-2 = {
            apiVersion = "v1";
            kind = "ConfigMap";
            metadata.name = "something";

            data."example.config" = "a = 123";
          };
        }
      '';
      default = { };
      # TODO: Implement better type definition
      type = types.attrsOf (types.either types.path types.anything);
    };

    kustomization = mkOption {
      description = "Kustomize config. Generally used to apply prefixes/labels";
      example = {
        namespace = "default";
        nameprefix = "dev-";
      };
      default = { };
      type = types.anything;
    };

    values = mkOption {
      description = "Helm deployment values";
      example = {
        something.oci.name = "something:v1";
        domain = "example.com";
      };
      default = { };
      type = types.anything;
    };

    utils = mkOption {
      description = "Output derivation containing deployment";
      example = literalExpression ''
        {
          # Converts attribute set to k8s-like env variable definition
          mkPodEnv = lib.mapAttrsToList (
            name: value:
              if (builtins.isString value) || (builtins.isNull value)
              then lib.nameValuePair name value
              else if builtins.isAttrs value
              then value // {inherit name;}
              else throw "Environment variable value can be either string or attribute set"
          );
        }
      '';
      default = { };
      type = types.attrsOf types.anything;
    };

    drv = mkOption {
      description = "Output derivation containing deployment";
      internal = true;
      readOnly = true;
      visible = false;
      type = types.package;
    };
  };

  config =
    let
      mkOutput = import ./mkOutput.nix { inherit pkgs lib; };
      output = mkOutput { inherit (config) name values chart templates helmArgs kustomization; };
      mkAction = execName: {
        inherit (output) drvPath type outPath outputName name;
        meta.mainProgram = execName;
      };

      postRenderer = pkgs.writeShellScript "kustomize.sh" ''
        set -euo pipefail
        TMP=$(mktemp -d)
        cat > $TMP/resources.yaml
        cp kustomization.yaml $TMP/kustomization.yaml
        kubectl kustomize $TMP
        rm -r $TMP
      '';
    in
    {
      _module.args = {
        inherit (config) utils values;
        chart = config;
      };

      helmArgs = lib.optionals (config.namespace != null) [
        "--namespace"
        config.namespace
      ] ++ lib.optionals (config.kubeconfig != null) [
        "--kubeconfig"
        config.kubeconfig
      ] ++ lib.optionals (config.context != null) [
        "--kube-context"
        config.context
      ] ++ lib.optionals (config.kustomization != { }) [
        "--post-renderer"
        postRenderer
      ];

      drv = {
        inherit (output) drvPath type;
        apply = mkAction "apply.sh";
        destroy = mkAction "destroy.sh";
        plan = mkAction "plan.sh";
        status = mkAction "status.sh";
      };
    };
}
