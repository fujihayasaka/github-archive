# secret-scanning-proto

This repo contains protobuf definitions for the [secret-scanning team](https://github.com/github/secret-scanning/).

**Making updates**

- Make sure to run `./script/generate-go` and `./script/generate-ruby`.
- For structural updates such as adding, renaming or removing directories containing protobuf files, update the `packages` list in our generation scripts accordingly -- [go](https://github.com/github/secret-scanning-proto/blob/main/config/tools/generate-go/generate)
  & [ruby](https://github.com/github/secret-scanning-proto/blob/main/config/tools/generate-ruby/generate).
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

> [!CAUTION]
> We recommend using a dotcom codespace for the below, as the TSS codespace is
> not in great shape :( We know, and will hopefully get around to it soon™

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
