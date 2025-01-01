# Development

Besides of what this document describes, and as a general rule of thumb:

- Our devenv is prepared to run in codespaces
- Our devenv uses docker + docker-compose + `make`.
- You shouldn't need to run things outside of that triad, If you need to you
  might be reading outdated docs or you should make sure you add support to
  docker + docker-compose + `make` to what you are doing.

## Dependencies

### Entitlements

While developing notifyd you might need access to some parts of the GitHub infrastructure and internal applications that you don't have by default. In order to get them you will need to create PRs to add yourself to the proper entitlements or install some applications, like the Viscosity VPN.

| Site                             | Entitlement/Access                                  | Reason                                                                                                                              |
| -------------------------------- | --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| [Hydro web][hydro-web]           | [Hydro okta entitlement][hydro-entitlement]         | To check hydro documentation and the event catalog                                                                                  |
| [Octofactory][octofactory]       | [Developer VPN][dev-vpn]                            | To generate and build the gems used to talk with the monolith-twirp-api                                                             |
| [Data Warehouse][data-warehouse] | [Data okta entitlement][data-warehouse-entitlement] | To check data about the published events and in the future to assist support                                                        |
| Notifyd's vault secrets          | [vault-secrets/notifyd.txt][vault-entitlement]      | To be able to handle secrets on production. You probably belong there already if you're on the pizza_team/notifications entitlement |

### Testing account

When testing our code we have mock accounts that
we can use to send notifications to our staff accounts without spamming our
teammates. You can easily create a mock account by just using
`yourhandle+something@github.com` where `+something` is an extra of your choice
to differenciate it from your main `yourhandle@github.com`. When you use your
mock account to notify your staff account, this will send notifications to your
staff account via the various channels enabled.

Once your mock account is confirmed, the next step would be to add it to [Team
discussions][test-org]. You can ask somewhere else in the team to add you
there. That org is only meant to be used for testing.

The repo used for testing purposes is [`notifications-go-test-repo`][test-repo]

These are the accounts used by the team when testing, please add yours!

| Team member                                    | mock account                                           |
| ---------------------------------------------- | ------------------------------------------------------ |
| [@abeaumont](https://github.com/abeaumont)     | [@abeaudont](https://github.com/abeaudont)             |
| [@franciscoj](https://github.com/franciscoj)   | [@not-franciscoj](https://github.com/not-franciscoj)   |
| [@jezcommits](https://github.com/jezcommits)   | [@jezno](https://github.com/jezno)                     |
| [@jhbabon](https://github.com/jhbabon)         | [@notbabon](https://github.com/notbabon)               |
| [@mrtazz](https://github.com/mrtazz)           | [@thisisamrtazzt](https://github.com/thisisamrtazzt)   |
| [@peter-evans](https://github.com/peter-evans) | [@not-peter-evans](https://github.com/not-peter-evans) |

#### Alumni

These folks where once members of the team, you might see them around on tests,
issues, etc :)

| Main account                                           | mock account                                           |
| ------------------------------------------------------ | ------------------------------------------------------ |
| [@dev-tim](https://github.com/dev-tim)                 | [@artem-artem](https://github.com/artem-artem)         |
| [@hussam-i-am](https://github.com/hussam-i-am)         | [@hussam-i-aint](https://github.com/hussam-i-aint)     |
| [@latentflip](https://github.com/latentflip)           | [@latentfrippery](https://github.com/latentfrippery)   |
| [@mikrobi](https://github.com/mikrobi)                 | [@probablymikrobi](https://github.com/probablymikrobi) |
| [@mrsimonfletcher](https://github.com/mrsimonfletcher) | [@callmefletch](https://github.com/callmefletch)       |
| [@vilacides](https://github.com/vilacides)             | [@isisen](https://github.com/isisen)                   |

## Getting Started

First, grab the repository (you can skip this step if you're working in a
codespace):

```sh
cd ~/github/ # Or whenever you place your cloned codebases
git clone git@github.com:github/notifyd.git
cd notifyd
```

## Testing

Our test suite is separated in two phases, a fast one and an integration one.
By default all tests will run inside `docker` through `docker-compose`. They'll
use the local directory to always fetch latest code changes.

### Running fast/unit tests

You can run them with:

```sh
make test-fast
```

You can run these tests locally instead of inside of the docker container with
the `ctx=local` flag:

```sh
make ctx=local test-fast
```

This suite is meant to run only tests that have no external dependencies. That
is, they don't use mysql, kafka or aqueduct.

### Running integration tests

The tests in the integration suite depend on the database and on kafka-lite and
aqueduct-lite. The `docker-compose` configuration starts all the dependencies
for you.

To run the integration tests through docker, run them with:

```sh
make test-integration
```

You can also run them locally, but you need the services running through
`docker-compose`.

You can run them with:

```sh
make dev-servers-detached # To start aqueduct-lite and kafka-lite in background
make ctx=local test-integration # to run the integration tests locally
```

### Running the whole suite

As with the integration tests, everything runs through `docker-compose`:

```sh
make test
```

If you want to run them locally, you need to have kafka-lite, aqueduct-lite and
mysql to run it:

```sh
make dev-servers-detached # To start aqueduct-lite and kafka-lite in background
make test
```

### Customizing the test command

You can customize which tests to run with the `TEST_ARGS` command and the extra
flags passed to `go test` with `EXTRA_TEST_FLAGS`, an example:

```sh
make test EXTRA_TEST_FLAGS=-p 2 TEST_ARGS=./internal/pkg/subscriptions/...
```

### Writing assertions

We use [testify][] for assertions.

Testify provides 2 different ways to assert in tests:

- `require` (it stops test execution when it finds a failing assertion, but it
  needs to run in the same goroutine as the test, which means you can't run
  `require` assertions on goroutines)
- `assert` (it continues test execution when it finds a failing assertion, but
  it works on goroutines different than the main test one. This means you can
  use `assert` assertions to goroutines, this is generally only needed for
  complex integration tests and you should rely on it as little as possible.)

### Writing fast/unit tests

Fast/unit tests are meant to have no dependencies on external systems (mysql,
kafka or aqueduct for example). If you mean to write a unit test and those are
needed, consider mocking them (See how to generate mocks in the next section)

### Autogenerated mocks

We use [testify][] to write assertions on tests and in particular we use
[testify-mock][] to build the mocks we use.

Writing these mocks by hand is a tedious and error prone process. Rather than
that we rely on code generation to do it for us when possible. We do it with
[`mockery`][mockery]. Check its [documentation][mockery] to better understand
how it works.

In the past `mockery` relied in `go generate`, but on the recent versions it
has migrated to a configuration file `.mockery.yaml` on the root of the
project.

`go generate` is a command included in the Go's default toolchain. It uses a
special annotation in form of comment in order to run code generation. It has
the following format (note there's no space between `//` and `go:generate`):

```go
//go:generate some-tool --arg1 --arg2
```

To generate mocks for a given interface:

1. You need to have the interface you're going to generate mocks for

   ```go
   // This is inside internal/pkg/code
   package code
   // MyInterface defines something that we want to do.
   type MyInterface struct {
      Method(ctx context.Context, arg string) error
      OtherMethod(ctx context.Context) error
   }
   ```

2. You need to add the interface to the `packages` portion of the config on
   `.mockery.yaml`.

   ```yaml
   ---
   # ... Default configuraiton
   packages:
     # ... Other packages
     github.com/github/notifyd/internal/pkg/code:
       interfaces:
         MyInterface:
   ```

3. Then we need to run this command to create the mock file:

```sh
make mocks
```

It will create a file in the same package as `MyInterface` mocking the methods
defined and we'll be able to use it easily on our tests :)

We use a wrapper for `go generate` (namely `make generate`) in order to run it
through docker and make sure that we all use a consistent version of `mockery`.

Example: In order to create mock for interface `APIClient` in [checker.go][],
first we've [added it to the config][checker-mockery-config] command to
checker.go, and after running `make generate`,
[`mock_checker.go`][mock-checker] has been created automatically. This way, we
can [use it in tests][mock-test] to [mock different methods][mock-methods] of
checker.go.

#### Special case: Mocking 3rd party interfaces

They follow the same rules, however you will need to directly specify the dir
in which you want to generate the mock for the interface. An example can be
this one we do for logs:

```yaml
packages:
  github.com/github/github-telemetry-go/log:
    interfaces:
      Logger:
        configs:
          - dir: internal/api/apiservice/mocks
            inpackage: false
            outpkg: mocks
          - dir: internal/pkg/job/middlewares/mocks
            inpackage: false
            outpkg: mocks
```

This generates 2 mocks for logs, one on the `apiservice` packages and another
one on the `middlewares` package.

They are also isolated on their own `mocks` package (that's why the `inpackage`
and `outpkg` options are for)

### Writing integration tests

Integration tests are meant to be used sparingly. They are slower and more
expensive, so they are not meant to be the one size fits all solution for all
our tests, only some of them that operate our system at top level.

For example:

- Sending a message to a consumer on the happy path, asserting all the expected
  side effects have taken place.
- Making a request to the API and checking that the side effects are correct.

More detailed/complicated assertions should rely on unit tests for that instead.

In order for a test to be run in the integration suite 2 conditions have to be met:

1. It has to have `Integration` on its name.
2. It has to skip running during `short` runs (`go test` has a `-short` flag
   that can be checked with `testing.Short()` while running tests)

An example:

```go
func Test_MyIntegration(t *testing.T) {
  if testing.Short() {
    t.Skip("skipping integration test")
  }

  // Rest of your testing code goes here.
}
```

### Writing tests that access the DB

The database is a core component in a lot of our packages, and we need to
access it in tests to check that our integration is working as expected.

Accessing the database during tests can be costly in terms of time and resource
management. For this reason it is recommended to build tests as
[suites][testify-suite] and use the `testhelper.DatabaseSuite` to setup and
close a single database connection per suite. This helper also sets up a
`testhelper.SequentialIDs` per suite that will provide new IDs on demand. These
IDs can be used to generate data that doesn't need to be cleanup between test
runs, thus reducing the need to truncate tables between tests. This will speed
up significally our test suite.

Example using the `testhelper.DatabaseSuite`:

```go
package example

import (
	"github.com/stretchr/testify/suite"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
)

type MyTestSuite struct {
	suite.Suite
	// Embed DatabaseSuite to get access to setup steps and DB instance
	testhelper.DatabaseSuite
}

func (s *MyTestSuite) TestDBAccess() {
	db := s.DB() // access the suite DB instance
	sq := s.SequentialIDs() // access the suite SequentialIDs instance
	// use sequential IDs to generate new IDs
	data := []{UserID: int64, Text: string}{{UserID: sq.Get(), Text: "test"}}

	for _, d := range data {
		err := saveData(d)
		s.Require().Nil(err)
	}
}


// Entry point for go test
func TestMyTestSuite(t *testing.T) {
	suite.Run(t, new(MyTestSuite))
}
```

If the `testhelper.DatabaseSuite` can't be used, consider the following points
to build a new test that uses the database:

- Create as little database connections as possible. Ideally one per test file
  (suite), or one per test.
- Make sure the connection is closed. On single tests, this can be done with
  `defer db.Close()`.
- Avoid truncating tables in the database on each test if you don't need to
  reuse IDs. Instead of cleaning up the database after each test, consider
  using new autogenerated IDs with the `testhelper.SequentialIDs` struct.
- Sometimes you need to truncate tables, and that's fine. It's better to make
  sure that these cases are the exception, not the norm.
- Cleanup the database with `testhelper.TruncateAllTables` after a test suite
  has run.

### Caveats

Our `make test-fast` suite still depends on the database in some cases. Ideally
we would move all those tests to the integration suite so that the tests on the
`fast` suite can run concurrently and faster.

The reason why we remove concurrency when running the integration tests is
because our database tests use a truncation strategy. If they run concurrently
then one test removes the fixtures from other tests and they fail.

## Linting

A github action will run [golangci-lint][] to lint for common errors. You can
also run this locally to check your code with:

```sh
make lint
```

## Code generation

Within the code base there are some parts that use code generation to make
life for us a bit easier. And for each of these use cases there exists a
dedicated generation `make` target:

- mocks (`make mocks`)
- protobuf definitions (`make protoc`)

On top of those there is also `make generate` which (re-)generates all of
these definitions in one run. So if you've made some changes, you can always
run `make generate` just in case anything needs updating.

## Vendoring

To vendor dependencies you can use the following `make` rule:

```sh
make vendor
```

## Database Migrations

### Creating a migration

1. First, generate new migration up and down files

   ```sh
   make shell-migration
   script/create-migration my-awesome-migration
   ```

   will create files like this:

   ```
   /Users/latentflip/go/src/github.com/notifyd/migrations/20210316151448_my-awesome-migration.up.sql
   /Users/latentflip/go/src/github.com/notifyd/migrations/20210316151448_my-awesome-migration.down.sql
   ```

1. Add SQL to your migration files

   ```sql
   -- /Users/latentflip/go/src/github.com/notifyd/migrations/20210316151448_my-awesome-migration.up.sql
   CREATE TABLE IF NOT EXISTS `my_awesome_table` (
     `awesomeness` int(11) NOT NULL
   ) ENGINE=InnoDB DEFAULT CHARSET=utf8;

   -- /Users/latentflip/go/src/github.com/notifyd/migrations/20210316151448_my-awesome-migration.down.sql
   DROP TABLE IF EXISTS `my_awesome_table`;
   ```

1. Run the migration locally

   ```shell
   make shell-migration
   script/migrate-mysql && APP_ENV=test script/migrate-mysql
   ```

   This should update files in the `schema/notifyd` directory.

   If any linting errors are reported by skeema, suggest fixing them and re-running your migration before continuing.

1. Commit everything, create a PR

1. Get team approval

1. Add the `migration:for:review` label to the PR. This will create a diff and
   give you instructions to get that migration into production. Long story
   short:

   - When it passes code review and CI is green you'll have to add a special
     label to the PR
   - This will ping the DB infra team
   - When they receive the ping they will run your migration

1. You're now OK to merge your PR :)

## Updating hydro schemas

### To update hydro schemas on the `notifyd` repo

1. Clone `git@github.com/github/hydro-schemas` somewhere on your system
2. Modify the schemas as per the [hydro-schema docs][hydro-schema docs]
3. To pull the changes into the generated go code run:

   ```bash
   script/pull-hydro-schemas $/path/to/checked-out/hydro-schemas $your-branch
   ```

4. This will regenerate the go-code from the specified branch. If you want to
   pull the schemas from main just set the branch to `main`

### Make hydro messages retriable

If you are adding a new message to our hydro schemas and you want it to be
retriable you need to make sure that this message includes the `Retries` entity
([example][retries-example]) and in addition to that you need to make sure it
has a wrapper that implements the `retriable` interface.

You can find examples [in our code][retriable-example]

### To update hydro schemas on `gh/gh`

You can follow [this example][hydro-schema-docs-the-hub] on the `hydro-schema`
docs on the hub.

## Updating monolith-twirp definitions

`notifyd` uses [monolith-twirp] to make calls back to our monolith. This works
by defining the services and methods in a .proto file and using it to generate
declarations in Go and Ruby. The files for the [monolith-twirp] definitions are
located in the [proto/monolith-twirp](../proto/monolith-twirp/) folder.

When we need to make changes to the .proto, we should follow [this
guide][monolith-twirp-changes]. The process requires two pull requests:

1. The first PR makes the relevant changes to the .proto file. Run `make
protoc` to update the generated Go declarations and include these in the PR
   alongside the .proto file. You can immediately start building programs that
   use the Go declarations in the same PR, though of course the monolith-twirp
   service will not yet provide those endpoints.

   If you've added new endpoints you may need to upgrade the mocks using this
   command:

   ```shell
   $ make mocks
   ```

   Before merging the PR, make sure you have updated the
   [`proto/monolith-twirp/notifyd/VERSION`
   file](../proto/monolith-twirp/notifyd/VERSION).

   Once this PR is merged, the monolith-twirp build system will generate the
   necessary Ruby Gems in Octofactory.

2. The second PR updates the Ruby client on `github/github` via a codespace.

   1. Enable the dev-vpn with the command below via a shell in the main
      directory of the [github/github](https://github.com/github/github)
      project.

      ```shell
      dev-vpn connect
      ```

      If this command does not work visit the
      [`#dotcom-codespaces`][#dotcom-codespaces]

   1. Run the command below

      ```shell
      script/vendor-monolith-twirp-gem notifications notifyd x.y.z
      ```

      `z.y.z` is the new version that you want to install.

      The first time you run this command you'll be given instructions on how
      to configure Octofactory.

   1. Once you have fixed followed the instructions you may run the command
      again to update the [monolith-twirp] gem.

Regarding PRs. you need to be careful because they might be order dependant!
Make sure that the changes you make are not backwards incompatible and that you
have a way to roll them out progressively.

As an example check these 3 PRs from [@dev-tim]

1. https://github.com/github/notifyd/pull/317
2. https://github.com/github/notifyd/pull/315
3. https://github.com/github/github/pull/190195

## Update the `notifyd-client` ruby client

[github/github][gh/gh] uses the `notifyd-client` to make requests to Notifyd's
services. The client will need to be updated whenever we make updates to the
[`proto/services`](../proto/services/) files. See instructions for udpating the
client in the [`notifyd-client` rubygem](./ruby-client.md) docs.

## Configuration and secrets

All the configuration you need is included in the `.env` file and on the
application defaults.

In case you need to add new secrets to the configuration make sure that you
don't add defaults for them and that you mark the mas "required" on the
configuration struct.

E.g.

```go
type Config struct {
  // [development, test, production]
  Environment        string `config:",env=APP_ENV"`
  PrimaryDatabaseURL string `config:",env=PRIMARY_DB_URL,required"`
  TestDatabaseURL    string `config:",env=TEST_DB_URL"`
  //...
```

This will make the app fail when booting with an error message when those are
missing as per the security requisites [listed here][security-env-vars]

To add the values on production you will need to use [vault]

## Distributed tracing

### Creating a new span

Set the following code at the beginning of a function or block to create a new span.

```go
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()
```

### Avoiding obfuscation of the `db.statement` attribute

SQL queries are automatically instrumented with tracing using the [otelsql][otelsql] library.
This produces traces containing the SQL query in the `db.statement` attribute.

When the OpenTelemetry Collector receives a trace with a `db.statement` attribute it will run it through a [processor that obfuscates queries][sanitize-db-statements] that may contain sensitive data.
The logic for this doesn't handle `JOIN` statements particularly well and they will be obfuscated.

We workaround this by quoting the identifier of the right-hand side table in the `JOIN` statement.
The OpenTelemetry Collector recognises the backtick as a quoted identifier and will not obfuscate the attribute.
e.g.
```SQL
DELETE from table_a AS a JOIN table_b AS b ON a.id = `b`.id WHERE ...
```

## Dotcom codespaces

Notifyd’s API can run on dotcom’s codespace development environment. The
feature can be used to iterate on the API development more quickly and test
specific scenarios that can’t be recreated easily in review-lab and or behind a
feature flag.

#### Starting the API

Eventually, the Notifyd API will be enabled automatically in dotcom, but for
now, you can use the following commands. Note that the API will run on port
8088 to avoid conflicts with other applications running on dotcom.

To start dotcom with the notifyd API

```bash
NOTIFYD_ENABLED=1 LOCAL_NOTIFYD=true script/server
```

To start dotcom with the notifyd API and enable all the feature flags

```bash
# to turn on all env variables for notifyd
NOTIFYD_ENABLE_FLAGS=1 NOTIFYD_ENABLED=1 LOCAL_NOTIFYD=true script/server
```

To start the API individually

```bash
NOTIFYD_ENABLED=1 LOCAL_NOTIFYD=true script/notifyd-server
```

#### Feature flag management

When the dotcom server is run with `NOTIFYD_ENABLE_FLAGS=1`, [this
script][ff-script] enables feature flags. Anyone who creates a feature flag for
notifyd should list the flag here to facilitate API development.

#### Version management

The [`config/notifyd-version`][notifyd-version] file determines the notifyd
version that the dotcom development environment uses. We should be sure to
maintain this file currently.

The sha in this file can be set to any version that has been pushed to
github.com. To run development with a specific version you can:

Change the sha in [`config/notifyd-version`][notifyd-version] Run the following
command:

```sh
build-subproject notifyd
```

## Legacy - Dotcom codespaces + Notifyd setup

Based on this PR https://github.com/github/notifyd/pull/519

Idea here to configure Notifyd instance to be running on same Codespaces machine as Dotcom.
![image](https://user-images.githubusercontent.com/5173831/141965948-acfe9d6a-5ec4-45ba-88b9-0b256d146bd3.png)

### How to use this codespaces setup?

1. Get a Github codespace and hop on the terminal section.
   ![image](https://user-images.githubusercontent.com/5173831/141995586-05413aa6-9405-4fc0-82d0-9336fa2738e0.png)

2. Run `./script/notifyd-codespaes-dev-environment-setup.sh -b <your branch
comes here>` script that is defined in this PR
   https://github.com/github/github/pull/200499

You can pass `-b` parameter to checkout specific branch of Notifyd, usually
it's `main`.

It's going to clone notifyd, run migrations enable feature flags, etc.
In the end if thing shave worked correctly you will see this prompt:

![image](https://user-images.githubusercontent.com/5173831/141995958-350e1056-50e6-4b83-86eb-a218af7be14c.png)

3. Now you can just open new terminal window and run Dotcom and Notifyd
   consumers.

Open new terminal window on codespaces:

```sh
cd /workspaces/github
./script/server
```

To run Notifyd consumer, open new terminal window on codespaces:

```sh
# Start Notifyd consumer
cd /root/go/src/github.com/github/notifyd && APP_ENV=development go run ./cmd/notify-consumer
# Start Delivery PN consumer:
cd /root/go/src/github.com/github/notifyd && APP_ENV=development go run ./cmd/deliver-mobile-push-consumer
# Start twirp API:
cd /root/go/src/github.com/github/notifyd && APP_ENV=development go run ./cmd/api/
```

5. Open Notifyd in codespaces:

```
code /root/go/src/github.com/notifyd
```

5. Enjoy E2E flow with debugging!

## Troubleshooting

### Error 1: Can't find hydro-schemas

```
Generating: notifyd/v0/notify.proto
script/pull-hydro-schemas: line 35: script/generate: No such file or directory
```

appears after running `script/pull-hydro-schemas $/path/to/checked-out/hydro-schemas $your-branch` [to update hydro schemas](https://github.com/github/notifyd/blob/main/docs/development.md#to-update-hydro-schemas-on-the-notifyd-repo).
This happens because arguments are wrong. Try to run command locally and use absolute path to find `hydro-schemas`.

## Legacy errors

These errors where once a problem on our devenv, they no longer are as we've
improved it over time, but we still keep those as reference.

<details>
<summary>Click to expand</summary>

### Error 1: Can't find mysqldump

```sh
script/migrate-mysql: line 23: mysqldump: command not found
```

or

```
mysqldump: Couldn't execute 'SELECT COLUMN_NAME, JSON_EXTRACT(HISTOGRAM, '$."number-of-buckets-specified"') FROM information_schema.COLUMN_STATISTICS WHERE SCHEMA_NAME = 'notifyd_development' AND TABLE_NAME = 'mobile_device_tokens';': Unknown table 'column_statistics' in information_schema (1109)

```

Make sure that you have `/usr/local/opt/mysql@5.7/bin` on your `PATH`.
You can normally get it done with `brew link mysql@5.7`

### Error 2: can't find skeema

```
Could not find skeema, even after installing. Are you sure that your GOPATH is in your PATH?
Migrating notifyd cluster...
```

appears after running `script/bootstrap`.
Make sure that you have your `gopath` in your `PATH`.

You can run `export PATH=$PATH:$(go env GOPATH)/bin` to solve the issue.

### Error 3:

```
panic: prepare test db: Error 1049: Unknown database 'notifyd_test'
```

appears after running tests with `go test ...`.

Try to run tests with prefix `APP_ENV=test go test ...` to solve the issue. Running tests with `make` should work as well. An alternative is to configure your IDE/editor to do this for you.

### Error 4:

```
test panicked: prepare test db: Missing value for required field "PrimaryDatabaseURL"
```

appears after running `make test` or any otehr testing command.
You can run `APP_ENV=test script/migrate-mysql` to solve the issue. This will prepare test db and run the migrations.

### Error 5:

```
Use 'docker scan' to run Snyk tests against images to find vulnerabilities and learn how to fix them
++ find ./proto/services -name '*.proto'
+ twirp_proto_paths=./proto/services/devicetokens/service.proto
+ for twirp_proto_path in '$twirp_proto_paths'
++ pwd
+ docker run --rm -v /Users/jezcommits/github/notifyd:/go/src -w /go/src notifyd-protoc --proto_path=. --ruby_out=./ruby/lib/notifyd --twirp_ruby_out=./ruby/lib/notifyd --go_out=. --twirp_out=. ./proto/services/devicetokens/service.proto
/lib64/ld-linux-x86-64.so.2: No such file or directory
```

appears after [running `script/protoc` locally to update ruby client](https://github.com/github/notifyd/blob/main/docs/ruby-client.md).
This happens because it depends on docker. In this case, the easy way to generate new code is to use Codespaces.

</details>

## Goproxy

To install internal dependencies we use [goproxy](https://github.com/github/goproxy).
To provide internal Go modules in your local machine follow [these setup instructions](https://goproxy.githubapp.com/setup).

### Codespaces

Goproxy is configured in Codespaces by default using the codespace's `GITHUB_TOKEN`. The codespace should have permissions to access internal GitHub repositories. If not, make sure you create a new one and bring permissions when asked.

### Docker

Inside docker containers Goproxy needs to be configured as well. All relevant docker-compose services have configured the proper Goproxy env vars. These use the `GITHUB_TOKEN` from the host environment by default, which means they work out of the box inside a Codespace.

The environment variables a docker container needs in order to make Goproxy to work are these:

```sh
GOPROXY=https://nobody:$GITHUB_TOKEN@goproxy.githubapp.com/mod,https://proxy.golang.org/,direct
GOPRIVATE=
GONOPROXY=
GONOSUMDB=github.com/github/*
```

## Codespaces and M1 devices

Since M1 devices have problems locally in dotcom that are solved using
Codespaces, some of these issues don't exist in `notifyd`:

- `script/pull-hydro-schemas` commands work better locally.
- `script/protoc-*` commands work better in Codespaces.

The rest of the commands should work well in both environments.

## Prebuilds

This repository has been enabled to use Codespace Prebuilds. This feature
creates a new Codespace template each time a push is made to the main branch so
that we don't have to install dependencies each time we start a Codespace. The
Prebuild job runs the `onCreateCommand` in this repo's `devcontainer.json`
file. A log of Prebuild jobs can be found [here][codespaces-prebuilds].

[#dotcom-codespaces]: https://github.slack.com/archives/C01S7MANE30
[@dev-tim]: https://thehub.github.com/engineering/products-and-services/internal/hydro/guides/adding-a-new-event/
[checker-mockery-config]: https://github.com/github/notifyd/pull/4213/files?filter=.moc#diff-531f7a01bb4f278f511fe2ada0896cfbbcb0771b7e53093d3a90c425882e4994R52-R54
[checker.go]: https://github.com/github/notifyd/blob/main/internal/pkg/dotcom/policy/checker.go
[codespaces-config]: https://github.com/github/notifyd/settings/secrets/codespaces
[codespaces-prebuilds]: https://github.com/github/notifyd/actions/workflows/codespaces/create_codespaces_prebuilds
[data-warehouse-entitlement]: https://github.com/github/entitlements/blob/master/ldap/apps/okta-network-gateway/data.txt
[data-warehouse]: https://data.githubapp.com
[dev-vpn-codespaces]: https://github.com/orgs/github/teams/engineering/discussions/575
[dev-vpn]: https://thehub.github.com/engineering/security/developer-vpn-access
[ff-script]: https://github.com/github/notifyd/blob/main/dotcom-codespaces-development/feature-flags
[gh/gh]: https://github.com/github/github
[golangci-lint]: https://golangci-lint.run/
[hydro-entitlement]: https://github.com/github/entitlements/blob/master/ldap/apps/okta-network-gateway/hydro.txt
[hydro-schema docs]: https://github.com/github/hydro-schemas
[hydro-schema-docs-the-hub]: https://thehub.github.com/engineering/products-and-services/internal/hydro/guides/adding-a-new-event/#ruby-project
[hydro-web]: https://hydro.githubapp.com/
[mock-checker]: https://github.com/github/notifyd/blob/7e034185e2920b4eb67c2d42669f570d04c80d0b/internal/pkg/dotcom/policy/mock_checker.go
[mock-methods]: https://github.com/github/notifyd/blob/69f07d8af57c27e139a156c10b8b56971eb7c2e6/internal/pkg/dotcom/policy/checker_test.go#L47
[mock-test]: https://github.com/github/notifyd/blob/69f07d8af57c27e139a156c10b8b56971eb7c2e6/internal/pkg/dotcom/policy/checker_test.go#L25
[mockery]: https://vektra.github.io/mockery/latest/
[monolith-twirp-changes]: https://github.com/github/monolith-twirp/blob/master/docs/workflow.md#making-changes
[monolith-twirp]: https://github.com/github/monolith-twirp
[notifyd-version]: https://github.com/github/github/blob/master/config/notifyd-version
[octofactory-token]: https://github.com/github/monolith-twirp/blob/master/docs/usage.md#installing-gems
[octofactory]: https://octofactory.service.private-us-east-1.github.net/
[otelsql]: https://github.com/XSAM/otelsql
[repo-secrets]: https://github.com/github/notifyd/settings/secrets/
[retriable-example]: https://github.com/github/notifyd/blob/main/internal/pkg/job/middlewares/retries/retriable_msgs.go#L22-L69
[retries-example]: https://github.com/github/hydro-schemas/pull/2455
[sanitize-db-statements]: https://github.com/github/otelcol/blob/main/config/otelcol/default/sanitize-db-statements.yaml
[security-env-vars]: https://thehub.github.com/engineering/development-and-ops/secure-coding/security-reqs-new-apps/#:~:text=Secrets%20environment%20configuration
[test-org]: https://github.com/orgs/team-discussions/people
[test-repo]: https://github.com/team-discussions/notifications-go-test-repo
[testify-mock]: https://github.com/stretchr/testify#mock-package
[testify-suite]: https://github.com/stretchr/testify#suite-package
[testify]: https://github.com/stretchr/testify
[update-gem-workaround]: https://github.com/github/ecosystem-api/issues/2753
[vault-entitlement]: https://github.com/github/entitlements/blob/master/ldap/apps/vault-secrets/notifyd.txt
[vault]: https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#viewing-and-setting-configuration-with-vault
