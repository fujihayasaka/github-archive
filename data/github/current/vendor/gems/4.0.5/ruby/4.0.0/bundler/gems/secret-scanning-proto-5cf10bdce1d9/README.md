# secret-scanning-proto

This repo contains protobuf definitions for the [secret-scanning team](https://github.com/github/secret-scanning/).

**Making updates**

- Make sure Docker is running before working with proto files locally; `./script/buf` runs buf inside Docker and pulls a GHCR-backed base image.
- Run `./script/buf format -w proto` to format proto files.
- Run `./script/buf lint proto` to check proto linting.
- Run `git fetch --depth=1 origin main && ./script/buf breaking proto` to check for breaking schema changes against `main`.
- Make sure to run `./script/generate` to generate go, ruby, typescript, and python code
- For structural updates such as adding, renaming or removing directories containing protobuf files, update the `packages` list in our generation scripts accordingly for code generation -- [go](https://github.com/github/secret-scanning-proto/blob/main/config/tools/generate-go/generate),
  [ruby](https://github.com/github/secret-scanning-proto/blob/main/config/tools/generate-ruby/generate), [typescript](https://github.com/github/secret-scanning-proto/blob/main/config/tools/generate-typescript/generate), & [python](https://github.com/github/secret-scanning-proto/blob/main/config/tools/generate-python/generate).
- For major RPC updates such as adding, renaming or removing an endpoint, update the [ruby client template](https://github.com/github/secret-scanning-proto/blob/main/_template/ruby/lib/secret_scanning_proto.rb) accordingly

**Updating dotcom**

In the `Gemfile` within `github/github`, find the entry for `secret-scanning-proto`. It should look
something like:

```
gem "secret-scanning-proto", github: "github/secret-scanning-proto", ref: "e56410c21be69c9f18e84d6374d0e62cd4c2dc06", glob: "gen/ruby/*.gemspec"
```

Update the `ref` and run:

1. `bundle install`
2. `bin/tapioca gem secret-scanning-proto`
3. `bin/tapioca dsl`

**Updating token-scanning-service**

In your `token-scanning-service` folder, run:

```console
go get github.com/github/secret-scanning-proto/gen/go
./script/update-vendor
# Make sure to run tests to make sure they are still passing
./script/test
```

A valid git revision can be appended to the end of the first command as `@your-branch-name` to test any changes before they're merged. For example:
```console
go get github.com/github/secret-scanning-proto/gen/go@your-branch-name
```

As secret-scanning-proto acts as a private go module, make sure you have
setup your workspace correctly to access this module. See the [getting-started](https://github.com/github/secret-scanning/blob/main/docs/getting-started-local.md#setup-one-time)
guide for some information, or more generically in [`github/go` docs](https://github.com/github/go/blob/master/docs/go-modules.md#publishing-and-consuming-go-modules)

**Updating token-scanning-asf-analyzer**

In your `token-scanning-asf-analyzer` folder, run the `asf_mvp/scripts/sync_proto.sh` script.
Note the instructions described at the top of the file.
