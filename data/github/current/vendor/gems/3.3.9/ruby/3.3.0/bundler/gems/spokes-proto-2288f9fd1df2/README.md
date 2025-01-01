# spokes-proto

Welcome to **Spokes Access API**, the home of internal programmatic access to Git repository data. With your help, we aim to build a replacement for `gitrpc`, where you, owners of services outside `github/github` can directly access Git repository data. In time, our aspiration is that [`github/github`](https://github.com/github/github) will drop its use of `gitrpc` and use Spokes Access API instead.

The architecture of Spokes Access API is that the Protocol Buffer definitions along with helpers for the supported languages reside in [`github/spokes-proto`](https://github.com/github/spokes-proto). The entrypoint to the API is using Twirp via [`spokesd`](https://github.com/github/spokesd), which will route requests to the relevant [`gitrpcd`](https://github.com/github/gitrpcd) backend. The `gitrpcd` backend will serve the incoming request, and assemble the response.

## Goals

* Provide a unified, resilient and performant API to Git repository data.
* Hide complexities relating to replicas and routing from callers.
* Abstract complexities from internal data models away from callers.

* Reduce coupling between data and consumers
    * This project will also create access to Git repository data from micro services. GitRPC uses a bespoke protocol and assumes deep knowledge of how Spokes works, which makes it unappealing to use from services outside of the monolith. This has led to designs where repository data is queried via the monolith, which puts more load on the monolith and injects it as a dependency.

* Secure by design
    * In addition, Spokes Access API provides a secure path to repository data. GitRPC does not encrypt its requests, Spokes Access API does (in dotcom). Spokes Access API encrypts uses mTLS to ensure that client apps are recognized, and it encrypts all request and response data in transit. Note: we do not currently do any authorization (e.g. is the actor or internal app allowed to access this repository).

* Reduced cost to scale
    * This project increases parallelism. GitRPC uses a single-threaded server, so our capacity is constrained by the number of ernicorn processes we run on the fileservers. Ernicorn processes have a relatively large footprint when compared with threads. Spokes Access API uses a single multi-threaded process on the server, so it has much less overhead per request and can handle much more parallelism.



## Getting Started

Follow our [Getting Started with Spokes Access API](docs/getting-started.md) guide, or read our [API documentation](gen/docs).

## Supported Languages

* Go ([example](examples/go))
* Ruby ([docs](gen/ruby)) ([example](examples/ruby))
* Rust (experimental)

## URLs

Depending on the environment you're running in, you'll need to use a different URL and may need to configure a client certificate.

Environment         | Authenication | Ruby Base URL                                                                       | Go Base URL
--------------------|---------------|-------------------------------------------------------------------------------------|-------------
github/github       | None          | `"http://127.0.0.1:28081/twirp/"`                                                   | `"http://127.0.0.1:28081"`
github/spokes-proto | None          | `:development` or `"http://127.0.0.1:12080/twirp/"`                                 | `"http://127.0.0.1:12080"`
github/spokes-proto | Request-HMAC  | `"http://127.0.0.1:12081/twirp/"`                                                   | `"http://127.0.0.1:12080"`
github/spokes-proto | Client cert   | `"https://127.0.0.1:12443/twirp/"`                                                  | `"https://127.0.0.1:12443"`
staging             | Client cert   | `:staging` or `"https://spokesd-staging.service.iad.github.net:10033/twirp/"`       | `"https://spokesd-staging.service.iad.github.net:10033"`
production          | Client cert   | `:production` or `"https://spokesd-production.service.iad.github.net:10013/twirp/"` | `"https://spokesd-production.service.iad.github.net:10013"`
staging             | Request-HMAC  | `"https://spokesd-http-staging.service.iad.github.net/twirp/"`                           | `"https://spokesd-http-staging.service.iad.github.net"`
production          | Request-HMAC  | `"https://spokesd-http-production.service.iad.github.net/twirp/"`                        | `"https://spokesd-http-production.service.iad.github.net"`
GHES                | No            | environment ([example](https://github.com/github/enterprise2/blob/32383deefd21603ed28baa4b7d85646168b07f5f/vm_files/etc/consul-templates/etc/nomad-jobs/github/00-env.hcl.ctmpl#L448)) | environment ([example](https://github.com/github/enterprise2/blob/044b305a206d3df5e44451445e844dbf81f9aef2/vm_files/etc/consul-templates/etc/nomad-jobs/token-scanning-service/00-token-scanning-service-env.hcl.ctmpl#L13))
GHAE                | No            | environment ([example](https://github.com/github/ghae-kube/blob/b255a2d2f2836e92f734ea08305c676c0a5efc51/ghae/charts/github/templates/shared-configmaps/instance-configmap.yaml#L162)) | environment ([example](https://github.com/github/ghae-kube/blob/4e71b08d58bb5305b17d29287bdcea1304576983/ghae/charts/token-scanning-service/templates/api.yaml#L98-L99))

## How To Contribute

To contribute to Spokes Access API, we would like to work with you to build the new APIs. Depending on your familiarity with Protocol Buffers, Golang and our internal services, we will work out a working agreement on how we collaborate on providing you with the data you need.

The general approach for contributing a RPC call is to:

1. Create the protobuf contract in `github/spokes-proto` and get that reviewed.
2. In `github/gitrpcd`, import the generated code from your branch in `github/spokes-proto` and implement the endpoint.
3. In `github/spokesd`, import the generated code from your branch in `github/spokes-proto` and implement the proxy route.
4. After deploying and merging the changes to `github/gitrpcd` and `github/spokesd`, merge the change in `github/spokes-proto`.
5. Add callers to the new endpoint in the consumer service(s).

Here is an example walkthrough of these steps in careful detail, using the migration of the `ahead-behind` endpoint from GitRPC to Spokes.

These steps are intended to be run in appropriate repository codespaces.

### Creating the protobuf definition in `github/spokes-proto`

**Example PR:** [proto: add ahead-behind protocol](https://github.com/github/spokes-proto/pull/205)

After determining the data types that you will need for your requests and responses,
create a branch in `github/spokes-proto` and add the definition in the `proto/spokes-api/`
directory.

> **Tip:** It is easier to add a new method to an existing API, especially when
> it comes to importing the generated code in later steps.

Look around at other example requests and response types. Requests should
always include `repository` and `context` fields, which are used internally by
Spokes API.  Optionally it can also include a `cursor` option.  After that, requests
should use a selector type for the bulk of the request data to remain flexible to
future changes to the endpoint.

Use existing data types from `proto/spokes-api/types` when possible, but create
new types within the API file if they are specific to your endpoint.

After [specifying your protobuf changes](https://github.com/github/spokes-proto/pull/205/commits/5ed609046c6eb1f59c906912cb1c585154e1400b),
create a draft pull request. Add your pull request to the [Git Access Iteration board](https://github.com/orgs/github/projects/6116/views/1)
and request a review in [`#spokes-api`](https://github.slack.com/archives/C01AM9W2TN0).
Review at this point is critical as it will save you a lot of rework if there
are any adjustments to make.

After your protobuf changes are stable, add some helper code and generate code.

- **Go**
    - In `_template/go/`, create constructors and validators for new types (including request types), along with unit tests.([example](https://github.com/github/spokes-proto/pull/205/commits/365f20dd76e4ffe65d7d77d77f257e81db0d279b))
    - Run `script/generate-go` to [update the Go code in `gen/go/`](https://github.com/github/spokes-proto/pull/205/commits/f1eb87d9505269d0800493efcc4b5dfd776f12d0).
    - Run `script/test-go` to run your new tests and to check for regressions in the generated Go code.
- **Ruby**
    - If you're adding a new `service`, add a factory method in [`_template/ruby/lib/github/spokes/proto/client.rb`](https://github.com/github/spokes-proto/blob/main/_template/ruby/lib/github/spokes/proto/client.rb). ([example](https://github.com/github/spokes-proto/pull/197/commits/0e40bc1dfe6d69a774184bc2488599211f75dd09))
    - If you're adding new types that you're going to use from Ruby and would like helpers for them, add them in `_template/ruby`. ([example](https://github.com/github/spokes-proto/pull/199/commits/040b5a83f845f2b8e291ab890a422703315cb128))
    - Run `script/generate-ruby` to update the Ruby code in `gen/ruby/`.
    - Run `script/test-ruby` to run the Ruby tests.
- **Rust**
    - In `rust/src/lib.rs`, add any needed `pub mod` clauses and appropriate calls to the `include!` macro.
    - Run `cargo build` in that directory to verify your changes. Unlike Ruby and Go, there is no generation step or Dockerfile: Rust macros take care of code generation consumer-side.
    - Run `cargo doc --open` and check that the new messages and client traits are present.
- **Docs** - `script/generate-docs` will [update the API docs in `gen/docs`](https://github.com/github/spokes-proto/pull/205/commits/72770b2c7c8e3cc75a9b18c312ac66ed17864c57).
- **Generate everything** - `script/generate` runs all of the generators.

At this point, make sure that the builds in `github/spokes-proto` pass, but
**do not merge your pull request**. We leave this pull request open until the
endpoint is fully deployed.

### Creating the endpoint in `github/gitrpcd`

**Example PR:** [ahead_behind: implement endpoint around `git ahead-behind`](https://github.com/github/gitrpcd/pull/1259)

`github/gitrpcd` is the service living on the Git fileserver that actually
performs the requested operation.

Before you can implement your new endpoint, you must import your generated code
from your `github/spokes-proto` branch.

Use the following commands to [import the `spokes-proto` Go library](https://github.com/github/gitrpcd/pull/1259/commits/bf31d383658066d5a23ebee88cfc936c1ee110af):

1. `go get github.com/github/spokes-proto/gen/go@<commit-id>`
2. `script/update-vendor`

> **Tip:** If you have difficulty with these commands, you may need to
> update your go proxy settings by running
>
> `rm ~/.netrc && /usr/local/share/goproxy-init.sh`

> **Tip:** If you created a new API in `github/spokes-proto`, then the
> `script/update-vendor` script will not actually pull in the relevant
> code because the API namespaces are not referenced. You will need to
> write your endpoint first in order to demonstrate those APIs are needed,
> and then run `script/update-vendor` again.

Now that the generated code is imported, you can
[implement the backend](https://github.com/github/gitrpcd/pull/1259/commits/a0b10e114eb181c3659bc50135d42d6f19ba6d14)
for your endpoint. Use adjacent API endpoints for inspiration.

Be sure to [add basic functionality tests](https://github.com/github/gitrpcd/pull/1259/commits/24ef6e45607637457a63f946546cfdfd14f7fd1b)
for your new endpoint. If this endpoint is generally a thin layer over a
Git builtin, you can rely on the tests in `github/git` for the base
functionality, but the `github/gitrpcd` tests should focus on any logic
around translating the service request to the process and parsing the
command output into a service response.

Add your pull request to the [Git Access Iteration board](https://github.com/orgs/github/projects/6116/views/1)
and request a review in [`#spokes-api`](https://github.slack.com/archives/C01AM9W2TN0).

After review, your endpoint is now ready to deploy and merge. There are no
callers at this point.

### Creating the proxy endpoint in `github/spokesd`

**Example PR:** [Add route for AheadBehind API](https://github.com/github/spokesd/pull/2115)

`github/spokesd` is the service that translates incoming requests and sends
them to an appropriate fileserver that contains a replica of the given
repository. You need to create a proxy endpoint for that translation.

Before you can implement the proxy endpoint, you must import your generated code
from your `github/spokes-proto` branch.

Use the following commands to [import the `spokes-proto` Go library](https://github.com/github/spokesd/pull/2115/commits/4f55a16477352d3bcf9840dc2f839afbc76eeafe):

1. `go get github.com/github/spokes-proto/gen/go@<commit-id>`
2. `script/update-vendor`

> **Tip:** If you have difficulty with these commands, you may need to
> update your go proxy settings by running
>
> `rm ~/.netrc && /usr/local/share/goproxy-init.sh`

Next, you need to [add your proxy route](https://github.com/github/spokesd/pull/2115/commits/0a68e4789d67a23536e5b8f4c1b69d94fbfd0e9e).
Luckily, this requires very little code change.

**New!** Be sure to add an [end-to-end test](https://github.com/github/spokesd/blob/main/services/gitrpcdproxy/e2e_test.go)
of your proxy endpoint.

Add your pull request to the [Git Access Iteration board](https://github.com/orgs/github/projects/6116/views/1)
and request a review in [`#spokes-api`](https://github.slack.com/archives/C01AM9W2TN0).

After review, your endpoint is now ready to deploy and merge. There are no
callers at this point.

### Merge the protobuf change in `github/spokes-proto`

**Example PR:** [proto: add ahead-behind protocol](https://github.com/github/spokes-proto/pull/205)

At this point, both `github/gitrpcd` and `github/spokesd` are using code
that exists in your branch of `github/spokes-proto`. You are free to merge
the change (there is no deploy involved).

This step now stabilizes the API.

### Consume the new API in the dependent service(s)

This step may look very different depending on which service is consuming
the endpoint.

At the moment, a very common case is that we are extracting an endpoint from
GitRPC in `github/github` to Spokes. In that case, we can carefully transition
using a Scientist experiment.

> For this section, we use the
> [conversion of the `blame_tree` endpoint](https://github.com/github/git-fundamentals/issues/1218)
> as our example.

#### Preparation Steps: Update version pins, gems, and generated code

First, [update the `github/gitrpcd` and `github/spokesd` version pins](https://github.com/github/github/pull/272804/commits/2ef7444c18b3469fe08c856b3f79d4847e7d58ef),
so the CI builds are using the versions with your endpoint implementations.

Then, [update the `spokes-proto` gem](https://github.com/github/github/pull/272804/commits/de71d34e37a0941728c9e52cfa77e31fb394e28e)
using

```
script/vendor-gem -r <oid> https://github.com/github/spokes-proto
```

to get your `github/spokes-proto` changes included.

Add [generated Spokes code](https://github.com/github/github/pull/272804/commits/e2722393cf27c573d18d7d63df1d65d59229d6e0)
using

```
bin/rails db:migrate db:test:soft_reset; bin/tapioca dsl -e test
```

At this point, it can be helpful to create and merge a change whose only purpose
is to [update these version pins and update the generated code]((https://github.com/github/github/pull/272804)).
This will reduce the window where you may have conflicts with other engineers
who are also updating generated code.

#### Create a Scientist experiment

In order to ensure we are matching the expected behavior during the conversion,
it is helpful to use a
[Scientist](https://thehub.github.com/epd/engineering/products-and-services/dotcom/scientist/)
experiment.

A helpful extraction is the
[`SpokesAdapter` module](https://github.com/github/github/blob/HEAD/packages/repositories/app/models/git_repository/spokes_adapter.rb),
which helps create a single place to run the experiment and feature flag
conversions.

After converting all callers to the new method, you can
[add a Scientist experiment to the `SpokesAdapter` module](https://github.com/github/github/pull/271896).

> This example of `blame_tree()` required converting some client-side caching
> over to the `SpokesAdapter` in order to ensure the Scientist experiment was
> comparing apples-to-apples situations and not getting confused between
> cached and non-cached examples. Hopefully this is a rare occurrence and
> most conversions do not need that extra work.

When the Scientist experiment is in place, all monolith tests assume the
experiment is enabled and will report if there is a mismatch during the
typical test cases. One thing that might trip you up is that some tests do
not have Spokesd enabled, so you'll need to
[update certain tests to enable Spokesd](https://github.com/github/github/pull/276291).
This can be helpful to do in its own PR, to avoid pinging too many code reviewers
as you iterate on the experiment itself.

The deployment should be low-risk due to the initially-inactive experiment.
Enable the experiment [in stafftools](https://admin.github.com/devtools/experiments/blame-tree).
Watch [the experiment dashboard](https://app.datadoghq.com/dashboard/9w5-jyh-t4n/scienceexperiments?tpl_var_experiment=blame-tree)
for performance statistics as well as mismatch records. You can look up the
exact mismatches in stafftools.

You can monitor the new endpoint being used in production via the
[Spokes API Twirp dashboard](https://app.datadoghq.com/dashboard/qay-urt-qxe/spokes-api-twirp?tpl_var_twirp_method%5B0%5D=blametree)
scoped to your endpoint.

As the experiment runs, you might need to
[update the experiment to handle any (expected) mismatches in results or exceptions](https://github.com/github/github/pull/280236)
before moving forward.

Since the experiment essentially doubles the amount of work done by these
requests, it is recommended to keep the experiment at a low percentage, if
possible, and to run it only for a short time. The goal is to gain confidence
in the endpoint in production before converting to a feature flag for the
wide-scale rollout.

#### Convert the experiment to a feature flag

Now that you've learned everything you want to learn from the experiment,
it is time to
[replace the experiment with a feature flag](https://github.com/github/github/pull/275054).

The feature flag rollout is done [via stafftools](https://admin.github.com/devtools/feature_flags/blame_tree_spokes).

Again, monitor the endpoint via the
[Spokes API Twirp dashboard](https://app.datadoghq.com/dashboard/qay-urt-qxe/spokes-api-twirp?tpl_var_twirp_method%5B0%5D=blametree),
but you could also construct [an endpoint-specific dashboard](https://app.datadoghq.com/dashboard/kvs-kpp-fbq/git-blame-tree)
comparing the GitRPC endpoint to the Spokes API endpoint.

#### Cleanup

Besure to [remove the feature flag and the GitRPC endpoint](https://github.com/github/github/pull/272891)
when the feature flag is at 100% for sufficiently long.

## Caveats

At the time of writing, there are a few caveats to using and contributing to Spokes Access API. We are actively working to overcome all of them.

* Authentication uses hand-rolled TLS certs.
* Only accepting APIs that are read only.
* Only accepting APIs that can be built in terms of `git` invocations.
* All request messages must have a `github.spokes.types.v1.Repository repository` field with ID = 1. `spokesd` uses this field to route the request to the correct backend server.

## SLOs

Currently we maintain two SLOs for Spokes API, one for availability (99.9% availability), and one for latency (p95 latency for a simple RPC is <100ms).  These can be found in the [Service Catalog](https://catalog.githubapp.com/services/spokesd/slos), and on [DataDog](https://app.datadoghq.com/slo/manage?query=assigned_team%3Agit-access).

## Contacting

* [#spokes-api](https://github.slack.com/archives/C01AM9W2TN0A) on Slack.
