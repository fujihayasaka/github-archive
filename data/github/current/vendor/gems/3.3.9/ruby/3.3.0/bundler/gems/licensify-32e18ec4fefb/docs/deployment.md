# Deployment
## Updating deployment configs
The deployment configurations for the production and Proxima environments are managed using [Kustomize](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/kustomize/kustomize-at-github/).

To make an update to the k8s deployment configs, e.g. adding an environment variable, follow these steps:
1. Make the relevant changes to the yaml files in the `config/kustomize/` directory. 
2. Run `script/kustomize`. This should build the Kubernetes files in the `config/kubernetes` directory. Verify the changes look good.