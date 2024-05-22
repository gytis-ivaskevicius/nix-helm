
# nix-helm

A Kubernetes deployment management tool powered by Nix.

## Motivation

Working with Helm templating can be messy and annoying. Utilizing a Turing complete language like Nix offers a more convenient and powerful approach for managing Kubernetes deployments.

## Features

- **Flexible Resource Definitions**: Define resources using either YAML or Nix expressions, allowing for a more versatile and expressive configuration.
- **Deployment Planning**: Plan deployments by diffing against the current state, ensuring you know exactly what changes will be applied.
- **Targeted Deployments**: Define deployment targets without the need for additional tools like `helmfile`.
- **Custom Resource Definitions**: Leverage the power of the Nix modules system to define custom resources which get converted down to standard K8s resources
- **Resource Overrides**: Use Kustomize-like resource overrides to customize and manage your Kubernetes resources easily.


## Example

### Definitions

**Environments definition:**

```nix
{pkgs, lib ? pkgs.lib, nix-helm}:
nix-helm.builders.${pkgs.system}.mkHelmMultiTarget {

  # Default configuration of the deployment. `final` refers to evaluated configuration after recursive merge
  defaults = final: {
    imports = [
      ./templates.nix
    ];

    # Helm arguments
    name = "ubuntu-example";
    chart = ./Chart.yaml;
    namespace = "dev";
    context = "eks-admin";
    kubeconfig = "$HOME/.kube/config";

    # kustomization.yaml config
    kustomization = {
      namespace = "default";
      nameprefix = "prefix-";
    };

    values = {
      image = "ubuntu:latest";
    };
  };

  # Definitions of particular targets. Attribute set overwrites `defaults` block
  targets = {
    prod = final: {
      namespace = "production";

      values = {
        image = "ubuntu:v1";
      };
    };

    dev = final: {
      namespace = "dev";

      values = {
        image = "ubuntu:v1";
      };
    };
  };
}
```

**`templates.nix` file:**
```nix
{lib, config, values, ...}:
{
  # Support for yaml files
  templates.something = ./something.yaml;

  # Support for nix expressions
  templates.ubuntu = {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = "ubuntu-deployment";
      labels.app = "ubuntu";
    };

    spec = {
      selector.matchLabels.app = "ubuntu";
      template = {
        metadata.labels.app = "ubuntu";
        spec = {
          containers = [
            {
              name = "ubuntu";
              # Passing image from values defined above
              image = values.image;
              command = [ "sleep" "123456" ];
            }
          ];
        };
      };
    };
  };

}
```


### CLI

These commands assume that deployment was imported into `flake.nix` as `legacyPackages.<system>.ubuntu`

**Viewing generated files:**
```bash
❯ nix build .\#ubuntu.first

❯ tree result/
result
├── bin
│  ├── apply.sh
│  ├── destroy.sh
│  ├── plan.sh
│  └── status.sh
├── templates
│  ├── ubuntu.yaml
│  └── something.yaml
├── Chart.yaml
├── kustomization.yaml
└── values.yaml
```

**Planning deployment:**

```diff
❯ nix run .\#ubuntu.first.plan                                                                                                                                         <aws:lw>
default, prefix-ubuntu, Deployment (apps) has changed:
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: prefix-ubuntu
    namespace: default
  spec:
    selector:
      matchLabels:
        app: ubuntu
    template:
      metadata:
        labels:
          app: ubuntu
      spec:
        containers:
        - command:
          - sleep
-         - "1234567"
+         - "123456"
          image: ubuntu:v1
          name: ubuntu
```

**Applying deployment:**

```diff
❯ nix run .\#ubuntu.first.apply                                                                                                                                          <aws:lw>
default, prefix-ubuntu, Deployment (apps) has changed:
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: prefix-ubuntu
    namespace: default
  spec:
    selector:
      matchLabels:
        app: ubuntu
    template:
      metadata:
        labels:
          app: ubuntu
      spec:
        containers:
        - command:
          - sleep
-         - "123456"
+         - "1234567"
          image: ubuntu:v1
          name: ubuntu


Do you wish to apply these changes to 'ubuntu-example'?
  Only 'yes' will be accepted to approve.

  Enter a value: yes

Release "ubuntu-example" has been upgraded. Happy Helming!
NAME: ubuntu-example
LAST DEPLOYED: Tue Mar  5 13:01:44 2024
NAMESPACE: default
STATUS: deployed
REVISION: 2
TEST SUITE: None
```

**Executing action on all targets:**

```diff
❯ nix run .\#ubuntu.ALL.plan                                                                                                                                            <aws:lw>


—————————————————————————————————————————————————————————
Executing plan on 'prod':

default, prefix-ubuntu, Deployment (apps) has changed:
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: prefix-ubuntu
    namespace: default
  spec:
    selector:
      matchLabels:
        app: ubuntu
    template:
      metadata:
        labels:
          app: ubuntu
      spec:
        containers:
        - command:
          - sleep
-         - "1234567"
+         - "123456"
          image: ubuntu:v1
          name: ubuntu


—————————————————————————————————————————————————————————
Executing plan on 'dev':

default, prefix-ubuntu, Deployment (apps) has changed:
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: prefix-ubuntu
    namespace: default
  spec:
    selector:
      matchLabels:
        app: ubuntu
    template:
      metadata:
        labels:
          app: ubuntu
      spec:
        containers:
        - command:
          - sleep
-         - "1234567"
-         image: ubuntu:v1
+         - "123456"
+         image: ubuntu:v2
          name: ubuntu

```

**Utility for converting yaml files into nix:**

```nix
❯ nix run github:gytis-ivaskevicius/nix-helm#yaml2nix-flatten ubuntu.yaml                                                                                                                                          <aws:lw>
{
  apiVersion = "apps/v1";
  kind = "Deployment";
  metadata.name = "ubuntu";
  spec = {
    selector.matchLabels.app = "ubuntu";
    template = {
      metadata.labels.app = "ubuntu";
      spec.containers = [
        {
          command = [
            "sleep"
            "123456"
          ];
          image = "ubuntu:v1";
          name = "ubuntu";
        }
      ];
    };
  };
}
```

