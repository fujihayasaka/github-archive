# What is this?

This lets us easily configure environment variables per stamp without messing with kustomize

- Environment variables added to `base` will appear in all environments
- Environment variables added to `proxima-base` will appear in all proxima environments
- Environment variables added to a folder will appear in the `stamp` which matches the folders name

Docs: https://thehub.github.com/epd/engineering/products-and-services/internal/moda/reference/environment-variables/#option-1-custom-configuration-format