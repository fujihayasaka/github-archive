# github

This package is a wrapper around [go-github](https://github.com/google/go-github). It is wrapped for two reasons:

1. **Add additional functionality**: The `go-github` package is a client for the REST API. There are UI-driven
   actions that we need to implement.
2. **Mocking**: The `go-github` package does not define any interfaces. This makes it difficult to write unit tests
   against.

This package will remain structurally similar to `go-github`. Interfaces will be introduced and functionality added.