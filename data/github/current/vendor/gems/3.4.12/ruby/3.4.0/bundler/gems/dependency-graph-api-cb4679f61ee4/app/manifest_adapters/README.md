# Manifest adapters

Manifest adapters allow the dependency graph to read dependency data from various dependency manifest formats (like `Gemfile` and `package.json` files). Adapters parse manifests and produce structured data in the form of `ManifestsAdapters::Manifest` instances.

## Adding a new adapter
A comprehensive playbook for implementing and shipping a new Manifest Adapter are [here](../../docs/add-new-ecosystems/adding-new-manifest-adapters.md).
