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
      type = types.either types.str types.path;
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

    helmArgs.plan = mkOption {
      description = "Helm arguments passed to `plan` action";
      example = [ "--debug" ];
      default = [ ];
      type = types.listOf (types.either types.str types.path);
    };

    helmArgs.apply = mkOption {
      description = "Helm arguments passed to `apply` action";
      example = [ "--debug" ];
      default = [ ];
      type = types.listOf (types.either types.str types.path);
    };

    helmArgs.destroy = mkOption {
      description = "Helm arguments passed to `destroy` action";
      example = [ "--debug" ];
      default = [ ];
      type = types.listOf (types.either types.str types.path);
    };

    helmArgs.status = mkOption {
      description = "Helm arguments passed to `status` action";
      example = [ "--debug" ];
      default = [ ];
      type = types.listOf (types.either types.str types.path);
    };

    copyToRoot = mkOption {
      description = "Files or directories to copy to root of the derivation. Used to pass additional configs";
      type = types.attrsOf types.path;
      default = {};
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
      output = mkOutput { inherit (config) name values chart templates helmArgs kustomization copyToRoot; };
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

      commonHelmArgs = lib.optionals (config.namespace != null) [
        "--namespace"
        config.namespace
      ] ++ lib.optionals (config.kubeconfig != null) [
        "--kubeconfig"
        config.kubeconfig
      ] ++ lib.optionals (config.context != null) [
        "--kube-context"
        config.context
      ];

      helmArgsWithRenderer = commonHelmArgs ++ lib.optionals (config.kustomization != { }) [
        "--post-renderer"
        postRenderer
      ];
    in
    {
      _module.args = {
        inherit (config) utils values;
        chart = config;
      };

      helmArgs.plan = helmArgsWithRenderer;
      helmArgs.apply = helmArgsWithRenderer;
      helmArgs.destroy = commonHelmArgs;
      helmArgs.status = commonHelmArgs;

      drv = {
        inherit (output) drvPath type;
        apply = mkAction "apply.sh";
        destroy = mkAction "destroy.sh";
        plan = mkAction "plan.sh";
        status = mkAction "status.sh";
      };
    };
}
