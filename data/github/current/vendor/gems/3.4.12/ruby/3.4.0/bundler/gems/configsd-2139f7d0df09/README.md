## ConfigsD

A domain service written in Go wrapping all access to the configurations mysql cluster.

### Additional Resources
* [Plan Doc](https://docs.google.com/document/d/13zY6gMAGroINeNCCM0skljXT3DEgmYVZD0m5ZQD1C28/edit?tab=t.0) (currently most up to date)
* [Project Toonie](https://docs.google.com/document/d/1JXj8Hsx94EeAflLjCgnCiUzXonDeL6m5RB2fjZG-pRM/edit?tab=t.0)
* [Epic Issue](https://github.com/github/monolith-fitness/issues/227)

### Hydro Schema File Generation

The protobuf schema files in this repository are generated from `.proto` files located in the [hydro-schemas repository](https://github.com/github/hydro-schemas). To regenerate them should the sources of truth change, follow these steps:

1. Open a codespace on `github/hydro-schemas`.
1. Run `mkdir go-out` to create an output directory for the generated Go files.
1. Run `script/generate --go-prefix=github.com/github/configsd/internal --go-out=/workspaces/hydro-schemas/go-out proto/hydro/schemas/github/repositories/v1/created.proto`.
1. Copy the generated files from `go-out` to the corresponding location in this repository, preserving the directory structure relative to the go prefix.
