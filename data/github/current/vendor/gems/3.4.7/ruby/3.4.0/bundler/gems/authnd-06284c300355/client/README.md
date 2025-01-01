# Authnd Go Client

A Go client to interact with the `authnd` RPC API.

## Usage

See [Go Client Docs](https://thehub.github.com/engineering/development-and-ops/authentication/authnd/go-client).

### Developing & Testing

To run the test suite:

```shell script
go test ./pkg/client
```

Go client tests are also run as part of the `make test` target.

### Releasing

Go client releases are managed via `git` tags for the `authnd` repo.
Once we have changes that we're ready to release to consumers, create a new release.
Follow [SemVer](https://semver.org) to choose appropriate version numbers and see [Semantic Import Versioning](https://research.swtch.com/vgo-import) for more guidance on Go module versioning.

#### Creating a new release

1. Checkout `main`, and `git pull`.
1. Ensure `client/version.go` is updated with the correct version number.
1. Ensure the changes you are intending to release are present
1. update [`client/CHANGELOG.md`](./CHANGELOG.md)
1. Run `script/make-go-client-release` to create a Go release. It will _automatically_ figure out the Git tag from the content of `client/version.go`, create the tag, push it, AND create a release using the content from the CHANGELOG (you can edit it after it's created).
1. Update the version of `github.com/github/authnd/client` in the server's `go.mod` file. This prevents dependabots from opening PRs to make a similar update ([for example](https://github.com/github/authnd/pull/1184)). It's not a problem if dependabot does open a PR like that, just noise.

To create the tag manually, run the following commands from `main` (this is an example for version 0.1.0):

```bash
git tag client/v0.1.0
git push --tags
```
