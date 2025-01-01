# actions-proto

The home for proto definitions and generated clients used in GitHub Actions services.

## 💾 Importing

```
go get github.com/github/actions-proto
```

This module uses _pseudoversions_ based on timestamp/git revision since we maintain forward/backward compatibility.

### Example

```go
import (
	eventsv1 "github.com/github/actions-proto/gen/go/results/events/v1"
)

func main() {
	update := eventsv1.WorkflowRunUpdated{}
	// ...
}
```

## 🧰 Tooling

For code generation, linting and breaking change detection, we use the [`buf`](https://docs.buf.build/tour/introduction/) CLI within a [Docker container](/config/tools/generate/Dockerfile) with volume mounts for a reproducable environment.

For a developer, the entrypoint is `script/buf`, you can pass command line arguments. For a full usage, see `script/buf --help`. We have convience scripts that call into this for a normal workflow.

Any dependencies (e.g. protoc plugins) are managed in [`versions.json`](/config/versions.json).

### 🖨️ Code Generation

`script/generate`: removes and regenerate _all_ code in `gen/`. The folder is deleted/recreated to prevent accidental leakage of old proto-generated code.

The generation output is determined by [`buf.gen.yaml`](/config/tools/generate/buf.gen.yaml), this is where the plugins, output, etc are defined.

## Ruby (optional)

If your service needs to generate Ruby code, you can add your services directory to [`ruby.json`](/config/ruby.json).

Since not all services need to integrate with Dotcom, the Ruby generation is opt-in.

This Gem can be consumed in Dotcom with `script/vendor-gem`. Example
```bash
script/vendor-gem -n actions-runner-admin  https://github.com/github/actions-proto
```

Note that `-n actions-runner-admin` corresponds to `actions-runner-admin.gemspec` in the top level of this repo.

To generate another gem, you will need to define a new `.gemspec` which points to the appropriate files.

## Typescript (optional)

If your service needs to generate Typescript code, you can add your services directory to [`ts.json`](/config/ts.json).

Then, generate the code with `script/generate` and copy the resulting files from `/gen/ts` to your desired project.

For example, here's how [`action/toolkit`](https://github.com/actions/toolkit) uses it for the [Artifacts API client](https://github.com/actions/toolkit/tree/45c49b09df04cff84c5f336f07d5232fa7103761/packages/artifact/src/generated).

### 🧹 Linting

`script/lint`: will lint all *.proto files against our configuration.

Our linting rules are not set in stone, if you wish to add _reasonable_ exceptions or modifications, edit the [`buf.yaml`](/config/tools/generate/buf.yaml). Read more on linting configuration on the [Buf Docs](https://docs.buf.build/lint/configuration).

### 🚨 Breaking Changes

`script/breaking`: protects us from making any changes that can break forward/backward compatibility.

Sometimes, especially in the early phases of a project breaking changes are acceptable. To bypass these checks, inlcude `[SKIP_BREAKING_CI]` in the title of the PR. 

Specifically, our script will check against the `main` branch of this repository.

## 🧑‍💻 Contributing

1. [Recommended] Spin up an [`actions-proto` Codespace](https://github.com/github/actions-proto/codespaces).
1. Create a new branch within the `actions-proto` repo. <br/> &nbsp;&nbsp;&nbsp;`git checkout -b <new-branch-name>`
1. Make your changes within the `proto/` directory.  Note that each service has its own directory.<br/>If necessary, you may create a new directory for your service.  (Be sure to adhere to existing versioning precedents.)
1. Run `script/generate` and perform a self-review of your changes (including their generated artifacts).
1. Commit, push, and create a new PR.
1. Verify that CI checks pass and seek PR approvals.
1. If everything is good, merge!
1. Run `go get -u github.com/github/actions-proto` in any repos that require the changes.

It's that easy™️
