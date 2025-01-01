# Installing Dependencies

Go modules in Launch are installed from GitHub repositories and [goproxy](https://github.com/github/goproxy).

See [monolith-twirp - Usage Guide](https://github.com/github/monolith-twirp/blob/master/docs/usage.md#go) for instructions specific to installing `monolith-twirp` modules.

## Go module proxy configuration

Follow the set-up instructions in the [user's guide to goproxy](https://github.com/github/goproxy/blob/main/doc/user.md#set-up).

## Installing a module

1. Run `go get` to install a new module or update an existing one:

    ```shell
    go get -u github.com/joshmgross/go-package
    ```

1. Consume the new module in your code

    ```go

    import (
    "github.com/joshmgross/go-package"
    )

    package.doSomething()
    ```

1. Tidy dependencies

    Clean up any unused dependencies or older versions if updating an existing module

    ```shell
    go mod tidy
    ```

## Redirecting module references

You can use the `replace` directive to redirect a module reference to another module. `go mod edit` is a good way to add these directives to `go.mod`.

1. Add or update a module replacement
    ```shell
    go mod edit -replace github.com/shurcooL/githubv4=github.com/github/githubv4@master
    ```

1. Tidy dependencies

    Clean up any unused dependencies or older versions if updating an existing module

    ```shell
    go mod tidy
    ```

## Troubleshooting



Example:

```shell
verifying github.com/github/go-twirp@v0.3.0/go.mod: checksum mismatch
	downloaded: h1:zY2FVP/fLd7+1vRRJddjq7ZnSQZvBs3uWhAnsXv4AAg=
	go.sum:     h1:tm3zwJ7OvHZEWj65x4IH0wj5nXhyyktKmEE7LURuu4Y=

SECURITY ERROR
This download does NOT match an earlier download recorded in go.sum.
The bits may have been replaced on the origin server, or an attacker may
have intercepted the download attempt.

For more information, see 'go help module-auth'.
```

As of January 2022 with https://github.com/github/launch/pull/4937, we're now fully off of Octofactory. You may still have a modcache with the checksums of the modules from Octofactory.

Running `go clean -modcache` should resolve this issue.

### I can't figure out an internal module's pseudo-version

Go uses [pseudo-versions](https://go.dev/doc/modules/version-numbers#in-development) for modules still in development.
We also rely on pseudo-versions to reference a newer major version without breaking module references,
for example `github/githubv4`.

To generate the pseudo-version, check out the version you want to use and run

```shell
    TZ=UTC git --no-pager show \
      --quiet \
      --abbrev=12 \
      --date='format-local:%Y%m%d%H%M%S' \
      --format="%cd-%h"
```

If you're adding or updating a dependency on a v0 module, you can use a branch name or tag in place of the pseudo-version. See example above with `github.com/github/githubv4@master`.

If you're still seeing issues, feel free to reach out in #launch or #gophers in Slack.
