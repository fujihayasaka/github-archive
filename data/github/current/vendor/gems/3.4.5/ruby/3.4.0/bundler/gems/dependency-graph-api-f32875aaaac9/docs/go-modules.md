# Go modules in GitHub's Dependency Graph

adonovan, Jul 14 2021

With thanks to zackfern, febuiles, sarahkemi, juxtin, pcarlisle,
iamwillbar at GitHub, and [Jay Conrod](mailto:jayconrod@google.com)
and [Russ Cox](mailto:rsc@golang.org) on the Go team.

In 2021 we added support for Go modules to GitHub’s
Dependency Graph (DG). This doc records various insights and choices
made, in the hope that it will simplify maintenance of the work and
guide the addition of new ecosystems to DG, such as Rust.

## Go modules

The v1.11 release of Go in 2018 was the first to include support for
modules. The Go module system has admirably comprehensive
[documentation](https://golang.org/ref/mod), so we’ll cover only the
essentials here. A module is a **collection of Go packages** with a
common prefix, such as
[go.starlark.net](https://pkg.go.dev/go.starlark.net/starlark) or
[github.com/github/go-stats](https://pkg.go.dev/go.starlark.net/starlark). A
module may contain a package in its root directory, in which case the
package and the module have the same name, but packages and modules
are distinct entities in different namespaces. Typically each VCS
repository provides exactly one module, defined by a go.mod file in
the root directory, but a larger repository may define several
modules, each corresponding to a subdirectory containing a go.mod
file. A legacy repository without a go.mod file may implicitly provide
a module that matches its domain name. Each go.mod file is usually accompanied by a go.sum file.

A **go.mod file**
[[example](https://github.com/google/starlark-go/blob/master/go.mod)]
specifies the name of the module (e.g. go.starlark.net), and thus
implicitly the name of each package provided by a subdirectory; the
required minimum version of Go; and the set of dependencies upon other
modules, including the required version of each one. The Go project
provides a [parser](https://pkg.go.dev/golang.org/x/mod/modfile#Parse)
for go.mod files.

The manifest files of different ecosystems---npm, Maven, etc---vary in
their **explicitness about dependencies**: for example, package.json
and pom.xml files mention only direct dependencies, whereas
package-lock.json files are complete or transitively closed. Go.mod files lie
somewhere in between: they record all direct dependencies, plus
indirect dependencies of modules that don't have an explicit go.mod
file, plus indirect dependencies that were upgraded beyond their
minimum version, plus possibly irrelevant packages in "untidy" go.mod
files. (Unnecessary dependencies are pruned by ‘go mod tidy’ and other
commands that are usually run prior to commit.) In the future, go.mod
files that require a version of Go >=1.17 will become transitively
closed. (This enables an optimization called [lazy module
loading](https://go.googlesource.com/proposal/+/refs/changes/80/220080/3/design/36460-lazy-module-loading.md).)
However, it will be many years before most go.mod files reach this
state, and in the meantime, with respect to dependencies, go.mod files
remain an underapproximation. By contrast, go.sum files contain the 
complete set of dependencies. 

A **go.sum file**
[[example](https://github.com/google/starlark-go/blob/master/go.sum)],
which lives alongside a go.mod file, records the cryptographic digest
of each dependency named in the go.mod file at the time it was first
downloaded. This “[trust on first
use](https://en.wikipedia.org/wiki/Trust_on_first_use)” approach
ensures that subsequent malicious tampering with the module’s supplier
does not go undetected. Starting with the Go 1.17 optimization
mentioned above, the go.sum file will hold distinct records for
complete modules and mere go.mod files: the former represent packages
actually required during the build due to a package-level dependency,
and the latter represent unnecessary dependencies due to the coarse
granularity of the module graph. Ignoring the /go.mod-suffixed entries
in the go.sum file provides a good approximation to the actual
package-level dependencies.

In many ways, Dependency Graph treats go.mod and go.sum files as Go's
analogues of NPM's package.json and package-lock.json files, respectively.
Go module dependencies are an **overapproximation of actual package
dependencies** (which, in turn, are an overapproximation of
function-level dependencies). For example, a package graph containing
import edges A1→B1 and B2→C2, grouped into modules A={A1}, B={B1,
B2},C={C2}, induces a module graph A→B→C, even though no package in
module A actually depends on code in module C. Thus, for the purposes
of vulnerability reporting, or computing a “software bill of
materials”, the dependency graph over Go modules obtained from manifest 
entries may imply dependencies on Go packages that aren’t actually used.

Go modules are published to a global **public registry** at
[proxy.golang.org](http://proxy.golang.org), with a subscribable index
at [index.golang.org](http://index.golang.org). The registry is a
secure cache of the usual [algorithm for
locating](https://golang.org/ref/mod#vcs-find) a Go module given its
name. Many organizations (including GitHub) run a registry for their
proprietary modules on a private network.

## Dependency Graph concepts

The three primary concepts in the Dependency Graph are “manifests”,
“packages”, and “package releases”.
In the Go ecosystem,
- a DG **manifest** corresponds to a go.mod or go.sum file;
- a DG **package** corresponds to a Go module (not a Go package); and
- a DG **package release** (also known as a **package version**) corresponds
  to the publication of a new Go module version at index.golang.org.

### Manifest ingestion

Each ecosystem in DG provides a Ruby function to parse the contents of
a file that has been identified as a manifest of that ecosystem. This
function is triggered by the github monolith [in response
to](https://github.com/github/github/blob/81753b84e39d9eadbe83a3a879be3c968dd59c35/app/models/push.rb#L485-L493)
the push of a commit that modifies a manifest. Because the go.mod file
is not a standard format such as JSON that is easy to parse in Ruby,
and a robust parser already exists in Go, the [Ruby
function](https://github.com/github/dependency-graph-api/blob/1200b910226ed04a0714d57e120cf35baf58b681/app/manifest_adapters/manifest_adapters/go_mod/adapter.rb#L17-L18)
for go.mod files fork+execs a Go program,
[gomod2json](https://github.com/github/dependency-graph-api/blob/master/go/ecosystem/go/gomod2json/gomod2json.go),
to parse the manifest and return its logical contents as a JSON value.
Go.sum files are parsed in [Ruby](https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/go/go_sum.rb#L18).

One effect of manifest ingestion is the
[creation](https://github.com/github/dependency-graph-api/blob/3d31c4aeca0ae7b0b3a1d402e366445cea70790e/etl/ingest/manifest_loader.rb#L90-L70)
(if absent) of a row in the DG 
[repositories](https://github.com/github/dependency-graph-api/blob/master/docs/tables.md#dg_repositories) table to record
information about the manifest’s **enclosing GitHub repository**,
including its id and name-with-owner (nwo), such as
github/go-stats. Without this repository record, package ingestion
cannot associate the correct repository with a package release: even
though the GH repo id and nwo may be known, there is no DG repository
id by which to refer to it. Consequently, manifest ingestion must
precede package ingestion. This is the natural course of events---a
GitHub package is authored in a git commit before it is published to
the world---but during backfill operations, it is crucial to ingest
manifests first. (This restriction could be lifted if we made
package-manager adapters (see below) responsible for reporting the
version control system that hosts the code; most package managers know
this information. Then package-release ingestion could create
repository records on demand.)

### Package-release ingestion and package creation

For each ecosystem, DG runs a package-manager adapter (PMA) process
that continually adds PackageRelease records for each new package. The
Go package manager, [gopma](https://github.com/github/dependency-graph-api/blob/master/go/ecosystem/go/gopma/gopma.go), is a long-running [job](https://github.com/github/dependency-graph-api/blob/master/config/kubernetes/workers/deployments/extract_go_packages.yaml) that subscribes to
index.golang.org updates. For each new Go module, it posts a
PackageRelease record, through Fjord/Hydro/Kafka, to a [PackageLoad](https://github.com/github/dependency-graph-api/blob/1200b910226ed04a0714d57e120cf35baf58b681/etl/ingest/package_loader.rb#L33)
ingest worker, which creates a row in the [package_versions](https://github.com/github/dependency-graph-api/blob/master/docs/tables.md#dg_package_versions) database
table. In addition, it creates (on demand) a row in the [packages](https://github.com/github/dependency-graph-api/blob/master/docs/tables.md#dg_packages)
table, which connects distinct versions of the same package. (I’m not
convinced the concept of package is necessary: most of the fields in
the package row are denormally copied into each package_version---no
bad thing, because many of these fields can in principle vary from one
version to the next. The only truly stable thing about a package is
its ecosystem and name, which could form an index to the
package_versions table.)

The Go PMA also resolves the source URL for the package. See [Repository
Mapping](#repository-mapping) below for details.

The PMA for Go differs from the other ecosystems in that it
communicates directly with Fjord, rather than using common code
(including a Resque hop) implemented in Ruby to do so. This was
unintentional---the use of Resque is [discreet and
flag-controlled](https://github.com/github/dependency-graph-api/blob/1200b910226ed04a0714d57e120cf35baf58b681/etl/ingest/package_processor.rb#L11)---but it doesn’t appear to have had adverse
effects. (It’s not clear to me what benefit Resque provides, other
than adding chat-ops-controlled spigots for event flow. But Resque has
its own complications. Does it carry its weight?)

### One-off adapter

A “one-off adapter” exposes the functionality of package-release
ingestion to a Slack chat-op, so that one can forcibly trigger the
re-ingestion of a package release, for example after a change in the
reingestion logic, or to repair damaged or jettisoned data. Again, it
is a thin [Ruby
wrapper](https://github.com/github/dependency-graph-api/blob/1200b910226ed04a0714d57e120cf35baf58b681/lib/one_off_importers/go.rb#L4)
around a Go helper program,
[gooneoff](https://github.com/github/dependency-graph-api/blob/master/go/ecosystem/go/gooneoff/gooneoff.go),
that uses the [same logic](https://github.com/github/dependency-graph-api/blob/master/go/ecosystem/go/internal/ingest/ingest.go) as gopma to read a single go.mod file from
proxy.golang.org and send a PackageRelease record through Fjord.

### Repository mapping

Whenever the set of
[packages](https://github.com/github/dependency-graph-api/blob/3d31c4aeca0ae7b0b3a1d402e366445cea70790e/etl/ingest/package_loader.rb#L65-L64) or
[manifests](https://github.com/github/dependency-graph-api/blob/3d31c4aeca0ae7b0b3a1d402e366445cea70790e/etl/ingest/manifest_loader.rb#L262-L262) changes,
the association of
packages to repositories is updated. For most ecosystems, this is a
heuristic that effectively joins the packages and manifests tables: a
newly published package needs to be associated with the repository
that holds the manifest that most plausibly defines it; and a new
manifest may require existing packages to change their repository
association. (As mentioned above, this process needn’t be heuristic:
package managers generally know exactly where source is hosted.)

Go is different. Heuristics for guessing the manifest for a DG package
work poorly for Go because a module may be hosted on one domain but
named for another. For example, the module named go.starlark.net is
hosted at https://github.com/google/starlark-go. Such “custom import
paths” are common in the Go ecosystem. The Go toolchain will parse the
import path for package names that start with a set of known hosts
(such as github.com), and otherwise must make an HTTP request to the
module name to [discover](https://golang.org/ref/mod#vcs-find) the
hosting location. The Go PMA invokes [this
logic](https://pkg.go.dev/golang.org/x/tools/go/vcs) and includes a
source URL in the PackageRelease record. The [repository-mapping
function for
Go](https://github.com/github/dependency-graph-api/blob/f0dd6abc8608a3113589c139177aea1c0d58ced5/app/models/package_to_repo_mapping/go_matcher.rb#L14)
exists to upgrade the certainty of this match so that it is considered
authoritative.


### Back-filling

Back-filling is the process of populating the database with historical
data after the logic for package or manifest ingestion is complete
or---heaven forfend!---after a significant change that renders the
existing data inadequate. Package-release backfilling is relatively
straightforward: by resetting the checkpoint to time zero, the gopma
program will start reingesting from the oldest packages, and will
catch up to recent changes over the course of several days. However,
because package-release ingestion relies on repository records
existing already, manifest ingestion must occur first.

I learned from the Go team that they had imposed a rate limit on us
during our first backfill because of operational problems caused by
the demand we presented. To reduce load on the proxy, they suggested
using the [Disable-Module-Fetch header](https://index.golang.org/), which allows the proxy to
report a cache miss for each cold entry instead of forcing it to
re-download the module, but I don’t think that would meet our need for
accurate old data, to which they suggested we use ‘go mod download’ as
a fallback when the proxy returns a cache miss, so that we pay the
cost instead of them.

If we ever need to repopulate the database from the public registry a
third time, we should make a complete local copy of all fetched
external data to avoid the need for a fourth---and future ecosystem
integrations should probably be designed that way from the outset. Go
module usage, and thus the work required to repopulate the database,
is growing exponentially.

Dependencies for manifests are computed when Dependency Graph is
notified that a manifest has been uploaded or modified. The [backfill
program](https://github.com/github/dependency-graph-api/blob/master/go/backfill/backfill.go),
will generate these change events for prior manifests.

TODO:
- build/test/docker/CI challenges

### Go monitoring metrics

- [Manifests ingested](https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?fullscreen_end_ts=1626300006000&fullscreen_paused=true&fullscreen_section=overview&fullscreen_start_ts=1626293408969&fullscreen_widget=358966610&from_ts=1626293408969&to_ts=1626300006000&live=false), by ecosystem
- [Packages ingested](https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?fullscreen_end_ts=1626341558543&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1626255158543&fullscreen_widget=358966662&from_ts=1626293408969&to_ts=1626300006000&live=false), by ecosystem (hint: deselect npm, which dwarfs all others)
- [Manifest ingestion (Kafka-)queue depth](https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?fullscreen_end_ts=1626341654049&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1626255254049&fullscreen_widget=3539099910280348&from_ts=1626293408969&to_ts=1626300006000&live=false), by ecosystem

### References

- [Issue #308](https://github.com/github/dependency-graph/issues/308), Add dependency graph support for Go. Contains links to all subtasks and PRs.
- [Operational playbooks for Go](playbooks/go.md)

