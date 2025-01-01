# Scripts directory

## Scripts you will probably run

Some of the scripts are intended to be run by people. These are roughly in the order that you might use them.

### script/setup

`script/setup` performs setup that only needs to run once in a launch dev environment. This includes creating the launch database.

### script/bootstrap

`script/bootstrap` installs or updates Go dependencies. There are still a few things, including the
`go` binary itself, that are not a direct module dependency and that `script/bootstrap` will ensure are installed.

`script/bootstrap --ruby` will do all of that and also install tools and libraries that are needed in order to run the github-launch client gem.

### script/build

`script/build` compiles the Go source into `bin/*`.

### script/test

`script/test` runs all of the tests. `script/test PACKAGE...` runs only tests for the specified packages.

### script/create-github-app

`script/create-github-app` will create a GitHub App in your local installation of `github/github` and store the app's identifier and private key for running Launch locally.

If `github/github` isn't installed in `~/github/github` you will need to pass it the path by `GITHUB_PATH=~/your/path/to/github/github script/create-github-app`.

### script/create-dependabot-app

`script/create-dependabot-app` will create a Dependabot App in your local installation of `github/github` and store the app's identifier and private key for running Launch locally.

If `github/github` isn't installed in `~/github/github` you will need to pass it the path by `GITHUB_PATH=~/your/path/to/github/github script/create-dependabot-app`.

### script/gofmt

`script/gofmt` runs go's built-in code formatter. It's advised that you run this before checking in, else the lint CI build will look upon your code disapprovingly.

### script/godoc

`script/godoc` runs go's built-in godoc tool and provides a browsable reference for the Go source in Launch.

### script/server

`script/server` builds launch and starts up all of the services.

### script/lint

`script/lint` is used by CI and can be used by you to check for code quality problems.

### script/dbconsole

`script/dbconsole` opens a mysql client, connected to launch's dev database.

### script/protoc

`script/protoc` converts `*.proto` into Go, Ruby and Node wrappers. When you modify a `.proto` file, you should call this and commit the updated `.pb.go`, `.rb` and `.js` files.

### script/skeema

`script/skeema` wraps invocations of skeema.

### script/sync-hydro-proto

`script/sync-hydro-proto` pulls down the latest hydro schemas for launch from https://github.com/github/hydro-schemas.

## Scripts you probably will not run (directly)

Many of the scripts exist to help out other scripts, or to support things like CI. These are listed in alphabetical order.

### script/cibuild\*

`script/cibuild-launch` is the main script for the "launch" CI build.

`script/cibuild-launch-lint` is the main script for the "launch-lint" CI build.

`script/cibuild` is used by `script/cibuild-launch`.

`script/cibuild-verify-image` is used by the "launch-build-docker-image" CI build. This CI build creates an image that will be used in production. `script/cibuild-verify-image` checks that the required binaries are present in the image.

### script/docker-compose

`script/docker-compose` wraps docker-compose and sets up some common config from `script/_serverenv`. It's used by `script/server` and `script/setup`. If you need to run docker-compose manually, you should use `script/docker-compose`.

### script/install-github-app

`script/install-github-app` installs the app created by `script/create-github-app` on the given repository.

### script/install-hydro-deps

`script/install-hydro-deps` installs software packages that we need in order to build the hydro client. This is normally only run in CI. Dev dependencies are handled by homebrew and the Brewfile.

### script/protoc-check

`script/protoc-check` verifies `script/protoc` does not change the working tree, to be certain `.pb.go`, `.rb` and `.js` in a commit match the commit's `.proto`.
This is only intended for CI.

### script/retry

`script/retry` is used by various other scripts to retry a command a certain number of times.

### script/\_server

`script/_server` starts up chatops, receiver, or deployer. This is used by script/server (via the Procfile).

### script/\_serverenv

`script/_serverenv` defines environment variables that configure launch services for dev. This is used by script/server and other scripts that it calls.

### script/with-test-db

`script/with-test-db` sets up a temporary mysql docker container with a `launch_test` database.

### script/bump-go-version

`script/bump-go-version` changes the Go version used by Launch, it updates our CI, Actions, and Dockerfiles.
