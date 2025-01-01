# Dependency Graph API database tables

This document describes the database tables used by the **Dependency
Graph API** application.

See [Dependency Graph API
Design](https://github.com/github/dependency-graph-api/blob/master/docs/design.md)
for a schematic overview of the system.

<!-- move this to design.md? -->

Tables are directly populated by the ingestion worker processes in
response to Kafka events.
For **packages**, the various [package-manager
adapter](../package_manager_adapters/README.md) processes run
periodically and send [PackageRelease
events](../package_manager_adapters/README.md#publishing-data) through
the `/package_releases` Fjord endpoint to the [PackageRelease Kafka
queue](https://hydro.githubapp.com/schemas/github-dependencygraph-v0-PackageRelease)
each time a package is added to the ecosystem.
The [`ingest_packages`](../script/etl/ingest_packages) worker reads
the Kafka events in a [loop](../etl/ingest/package_stage.rb), and for
each one it calls [`PackageLoader.load`](../etl/ingest/package_loader.rb)
to update various tables.

For **manifest-file changes**, the [GitHub monolith](https://github.com/github/github/blob/5a99ebfb6712ccfc006dcefd7ff547c2ca7a3397/config/instrumentation/hydro/subscriptions/kitchen_sink.rb#L423), in response to git pushes, posts events to the [RepositoryManifestFileChange Kafka
queue](https://hydro.githubapp.com/schemas/github-dependencygraph-v0-RepositoryManifestFileChange).
The [`repo_manifest_file_changes`](../script/etl/repo_manifest_file_changes) ingestion worker
calls [`RepositoryManifestFileChangeProcessor`](../etl/ingest/repository_manifest_file_change_processor.rb`) which consumes events from Kafka through Hydro.
For each one it calls [`ManifestLoader.load`](../etl/ingest/manifest_loader.rb) to
[update](https://github.com/github/dependency-graph-api/blob/master/etl/ingest/manifest_loader.rb#L126-L142)
the manifest and manifest dependency tables,
and related tables such as **repositories**.
(In future, we may bypass the monolith by having the ingest process listen directly to the Hydro channel for git pushes.)
<!-- Some context:
  https://github.com/github/dependency-graph/issues/321
  https://github.com/github/dependency-graph-api/pull/1903
-->

Manifest parsing is also exposed as a service by the DG API server:
its [GraphQL interface](../app/graphql/api/types/root.rb) dispatches
to the relevant manifest parser and returns a [parsed
manifest](../app/models/parsed_manifest.rb).  It is called from [the
monolith](https://github.com/github/github/blob/df9ea077a31caac0213ac6f161b840be7b4ccdc4/lib/dependency_graph/dynamic_manifests_query.rb#L31)
for the
[RepositoryVulnerabilityAlerter](https://github.com/github/github/blob/df9ea077a31caac0213ac6f161b840be7b4ccdc4/app/models/repository_vulnerability_alerter.rb#L61)
to create vulnerabiliy alerts at certain moments in the repository
lifecycle.
<!-- vague, but I'm not sure what "dependency graph initialization means"
https://github.com/github/github/blob/df9ea077a31caac0213ac6f161b840be7b4ccdc4/app/models/automatic_app_installation/handlers/dependency_graph_initialized.rb#L41 -->


### Entity-relationship diagram

Each node is the entity for a single row in the corresponding table (selected tables only).
Edges denote foreign-key relationships.

![E/R diagram](https://docs.google.com/drawings/d/e/2PACX-1vSXcrYpYx6-Ee4PF8XjSir6MC2CD3GE5ky0aKSgA_CcihflPtbq92Q1vwbJAiq6v6z2_8bC2utua0Ap/pub?w=934&h=539)
<!-- editable: https://docs.google.com/drawings/d/1DNFjSBn1g18TU9Nh9tIEi_p_ppFk4yrER164wAAixZU -->

TODO: add edges for secondary indexes, and dotted edges for one-to-many indexes.

## Tables

All our table names use the prefix `dg_` to avoid naming collisions
between the GitHub database and the Dependency Graph database when
running on Enterprise; see
[this issue](https://github.com/github/croquet/issues/113) for more
information.

Every table has an indexed, auto-incrementing numeric `id` field as
its primary key; these fields are not documented explictly below.
In some tables these IDs are used as keys: for example
`dg_package_versions.package_id` is a foreign key for
`dg_packages.id`. But in other tables they are unused because the
table has a unique and indexed key that is more meaningful and
convenient, such as the `name` field of `dg_checkpoints`.
Despite the redundancy, the `id` may be prudent in case the meaningful
key should unexpectedly prove non-unique, it may make Rails and
GraphQL integration smoother, and it is more compact than a meaningful key.

Any secondary (non-`id`) indexes of each table are noted below.
Some of these indexes include the `id` field; the apparently redundancy
may have the purpose of ensuring stability of repeat queries caused by pagination.
Index order [matters](https://stackoverflow.com/questions/24315151/does-order-of-fields-of-multi-column-index-in-mysql-matter), at least in InnoDB tables.
For more on index design, see [these slides](https://www.slideshare.net/billkarwin/how-to-design-indexes-really).

Many tables have a column named `repository_id`. In some cases, it is
a key to the GitHub
[repositories](https://data.githubapp.com/sql/5310e315-1c0b-4165-8ecd-19bcd9479b0c)
table; in others, it refers to our `dg_repositories` table. The
documentation of each field and foreign key below is explicit, but
readers should bear the distinction in mind.

Most tables have `created_at` and `updated_at` fields; they are
self-explanatory and not documented below.

Sample queries are shown for each table. We use Rails as an example,
as it is a public repository that provides a variety of packages, has
numerous dependencies (prerequisites) and dependents (Rails
applications), and is familiar.

Dependency edges in manifest files are not equivalent.
Some manifests, like `package.json` and `pom.xml`, enumerate the direct
edges corresponding to the import statements of the associated package.
Others, like `go.mod`, include direct edges plus some indirect edges,
such as those inferred from dependencies that don't have an explicit module file,
or those upgraded beyond the minimum required version.
And others, like `package.lock`,
enumerate all the indirect dependencies computed by the package manager.
Our database does not record this distinction,
even when the manifest file does. Therefore to enumerate
all the dependencies of an arbitrary manifest, the consumer of the
data is responsible for the fixed-point iteration, even though for
certain package managers this step is unnecessary.

Table schemas cannot be created or changed by executing SQL statements in production;
our account does not have the necessary capability. Instead, we must use
[Skeefree](https://github.com/github/skeefree/blob/master/docs/how.md)
for migrations. This typically requires adding a `db/migrate/*.rb`
file that defines the schema change, running `bin/rails db:migrate`
to apply the schema change to the local MySQL database and then dump the
schema of the local database in `db/structure.sql`,
mailing a PR for approval by our team and by
`database-infrastructure`, and then waiting for a robot to apply the
change to the production database.

### `dg_packages`

A row in this table represents a software package published to a
registry such as RubyGems or NPM, independent of any particular
version. This table provides information about a package such as its
GitHub repository.

Packages are uniquely identified by their opaque `id`, and also by the
pair (`package_manager`, `name`). This pair is used as a foreign key
by several other relations.

- **name** (String) The normalized name of the package (as used by other database tables).
   It may differ from label due to normalization rules such as Python's
   [PEP-503](https://www.python.org/dev/peps/pep-0503/).
- **label** (String) The original textual name of the package from the source registry,
   if it differs from the normalized name.
- **package_manager** (Integer) Enum which maps to a PackageManager ([Reference](https://github.com/github/dependency-graph-api/blob/41dc9cbbc4b3c1258f051090baee563f8ad25c20/app/models/types.rb#L2-L11))
- **repository_id** (Integer) The GitHub ID of the repository that (probably) contains this package.
- **last_published_at** (Datetime)
- **repository_id_certainty** (Integer) A rating of how certain we are of the mapping to the repository. Ranges from 90 (manual override) to 0. See [certainty.rb](../app/models/package_to_repo_mapping/certainty.rb) for details.
- **repository_nwo** (String) GitHub repository "name with owner" of
    the repository that (probably) contains this package.
    Denormalized to save a join with the GitHub `repositories` table.

Size at Apr 2021: 3.5M rows, 1.2GB on disk; scan time < 2s.

Secondary indexes:
- name, package_manager (unique)
- last_published_at
- repository_id
- package_manager, repository_id
- repository_nwo

A package is [mapped to a
repository](https://github.com/github/dependency-graph-api/blob/e9eb1ee49b872ef7a10dfe708c1dfd0d4a9de7d8/app/models/package_to_repo_mapping/strong_matcher.rb#L17-L02)
by scanning the (probable) GitHub repository for a [manifest](#dg-manifests) that
defines (`package_manager`, `name`).

<details>
  <summary>Example: show package id and repository of Ruby Gem named 'rails'</summary>

```text
mysql> select id, repository_id, repository_nwo from dg_packages where package_manager = 1 and name = "rails";
+------+---------------+----------------+
| id   | repository_id | repository_nwo |
+------+---------------+----------------+
| 2066 |          8514 | rails/rails    |
+------+---------------+----------------+
```
</details>

<details>
  <summary>Example: show packages (Ruby Gems) defined by Rails repository (GitHub ID 8514)</summary>

```text
mysql> select id, name, repository_nwo from dg_packages where repository_id = 8514;
+------------+-----------------------------------+----------------+
| id         | name                              | repository_nwo |
+------------+-----------------------------------+----------------+
|       2060 | activesupport                     | rails/rails    |
|       2061 | activemodel                       | rails/rails    |
|       2062 | activerecord                      | rails/rails    |
|       2063 | actionpack                        | rails/rails    |
|       2064 | actionmailer                      | rails/rails    |
|       2065 | railties                          | rails/rails    |
|       2066 | rails                             | rails/rails    |
|       3601 | actionview                        | rails/rails    |
|       4514 | activejob                         | rails/rails    |
|     218520 | actioncable                       | rails/rails    |
|   13814123 | vipul_actioncable                 | rails/rails    |
|   49466346 | activestorage-with-source-code    | rails/rails    |
|  186376596 | actioncable-including-source-code | rails/rails    |
|  203609211 | actioncable-modernized            | rails/rails    |
|  203768219 | actioncable-with-source-code      | rails/rails    |
|  453592232 | @rezonant/actioncable             | rails/rails    |
|  455825189 | @rmacklin/actioncable             | rails/rails    |
|  466638528 | @rails/ujs                        | rails/rails    |
|  466638534 | @rails/actioncable                | rails/rails    |
|  466638539 | @rails/activestorage              | rails/rails    |
|  466638544 | @rails/actiontext                 | rails/rails    |
| 1161420802 | rails-ujs-thuocsi                 | rails/rails    |
| 1991759744 | @dolsem/actioncable               | rails/rails    |
+------------+-----------------------------------+----------------+
```
</details>


### `dg_package_versions`

A row in this table represents a released version of a package.
Rows are added by the package-manager programs for each external registry,
which run periodically.

- **package_id** (Integer) identity of released package (foreign key to `dg_packages.id`).
- **name** (String) The _version_ of the package, using the package manager's notation,
   which is usually similar to [SemVer](https://semver.org/), at least superficially.
- **encoded** (BigInt) The `major.minor.patch` components of the
    version encoded in base 2<sup>16</sup>. This allows the database
    to efficiently compute version ordering, but only approximately:
    the version's suffix components such as pre-release labels and build tags are ignored.
    (Not all package managers are fully SemVer-compatible, though they tend to agree
    on the interpretation of purely numeric versions. For details, see:
    [Nuget](https://docs.microsoft.com/en-us/nuget/concepts/package-versioning),
    [Go mod](https://golang.org/ref/mod#versions),
    [Pip](https://www.python.org/dev/peps/pep-0440/#version-scheme),
    [Maven](https://maven.apache.org/pom.html#Version_Order_Specification),
    [Composer](https://getcomposer.org/doc/articles/versions.md),
    [Npm](https://docs.npmjs.com/about-semantic-versioning),
    [RubyGems](https://guides.rubygems.org/patterns/),
    [Poetry](https://python-poetry.org/docs/dependency-specification/).)
- **published_at** (DateTime) When this version was originally published to the source registry.
- **unpublished_at** (DateTime) When the version was removed from the source registry, if applicable.
- **license** (String) The license under which the package is released. We get this data from [Clearly Defined](https://clearlydefined.io).
- **clearly_defined_score** (Integer) Clearly Defined's license score. (See their [formula](https://github.com/clearlydefined/license-score/blob/master/ClearlyLicensedMetrics.md#clearlylicensed-scoring-formula) for details.)
- **external_id** (Integer) Unused.
- **pushed_at** (Integer) Obsolete.

The following additional fields are all denormalized from `dg_packages` to save a join:

- **package_manager** (Integer) PackageManager enum.
- **package_name** (String) The name of the package.
- **repository_id** (Integer) The GitHub ID of the repository that (probably) contains this package.
- **repository_id_certainty** (Integer) A rating of how certain we are
    of the mapping to the repository.
    Ranges from 90 (manual override) to 0.
    See [certainty.rb](../app/models/package_to_repo_mapping/certainty.rb) for details.
- **repository_nwo** (String) "name with owner" of the GitHub
    repository that (probably) contains this package.

Size at Apr 2021: 4M rows, 20GB on disk; scan time 18s.

Secondary indexes:
- package_id, name (unique)
- package_id
- name
- repository_id
- package_id, encoded
- repository_nwo
- license
- package_name, package_manager, name
- package_id, repository_id

<details>
  <summary>Example: show version history of packages (Ruby Gems) released into Rails repository (GitHub ID 8514)</summary>

```text
mysql> select p.name, pv.name, pv.package_name
       from dg_packages as p, dg_package_versions as pv
       where pv.package_id = p.id and pv.repository_id = 8514
       order by p.name, pv.name;
+-----------------------------------+------------------------------------+-----------------------------------+
| package.name                      | package_versions.name              | package_versions.name             |
+-----------------------------------+------------------------------------+-----------------------------------+
...
| rails                             | 0.9.3                              | rails                             |
| rails                             | 0.9.4                              | rails                             |
| rails                             | 0.9.4.1                            | rails                             |
| rails                             | 1.0.0                              | rails                             |
| rails                             | 1.1.0                              | rails                             |
| rails                             | 1.1.1                              | rails                             |
| rails                             | 1.1.2                              | rails                             |
...
```
</details>


### `dg_repositories`

This table provides information about GitHub repositories.
(The canonical information lives in the `repository` database on another server.)

- **github_repository_id** (Integer) ID of the repository in the GitHub database. Uniquely indexed.
- **github_owner_id** (Integer) ID of the repository owner in the GitHub database.
- **public** (Bool) Whether the GitHub repository is public.
- **nwo** (String) "name with owner" of the GitHub repository.

Size at Apr 2021: 3M rows, 7GB on disk; scan time > 7s.

Secondary indexes:
- github_repository_id (unique)
- github_repository_id, public
- nwo, public
- github_owner_id, public

<details>
  <summary>Example: show DG repository ID for Rails repository (GitHub ID 8514)</summary>

```text
mysql> select id, nwo, github_owner_id from dg_repositories where github_repository_id = 8514;
+-------+-------------+-----------------+
| id    | nwo         | github_owner_id |
+-------+-------------+-----------------+
| 12629 | rails/rails |            4223 |
+-------+-------------+-----------------+
```
</details>

### `dg_manifests`

A row in this table represents a particular manifest
file: its subdirectory and filename, type (e.g. Gemfile,
package.json), containing repository, package manager and name,
revision number (if available), and git commit.

Rows in this table are updated (preserving `id`) as commits of new
revisions are pushed; historical information is not retained.

- **repository_id** (Integer) The containing repository (foreign key to `dg_repositories.id`).
- **manifest_type** (Integer) [Type](https://github.com/github/dependency-graph-api/blob/41dc9cbbc4b3c1258f051090baee563f8ad25c20/app/models/types.rb#L21-L51) of manifest (e.g. `Gemfile` or `pom.xml`)
- **package_manager** (Integer) PackageManager enum; see `dg_packages.package_manager` for details.
- **name** (String) Name of the importable package declared by this manifest,
   or null for manifests that don't declare the name of a package,
   such as Gemfiles, or `go.mod` files in forked repositories.
- **revision** (Integer) The number of times this manifest has been processed.
    Used by `dg_manifest_dependencies` represent whether a dependency is present in this manifest.
- **latest_git_ref** (String) Git commit hash of last update to this manifest.
- **last_pushed_at** (DateTime) Time associated with that commit.
- **filename** (String) Base name of manifest file (e.g. `Gemfile.lock`).
- **path** (String) Name of parent directory of manifest file, or "" for repository root.

```
Q. Why is `filename` empty for 336 rows. Bad data?
   Reid suspects a "pseudo manifest".
   Justin says this is perhaps from the [vintage](https://github.com/github/vintage) service,
   which synthesizes virtual manifest files for implicitly vendored JavaScript; but
   the number of empty filenames seems too small for that to be the explanation.
   Also `vintage` would use the name of the vendored file for the virtual manifest. So not that.
```

Size at Apr 2021: 80M rows, 26GB on disk; scan time 40s.

Secondary indexes:
- repository_id, manifest_type, path, filename (unique)
- name
- package_manager, name

<details>
  <summary>Example: show latest revisions of all manifest files in the Rails repository (dg_repository.id=12629)</summary>

```text
mysql> select id, path, filename, manifest_type, revision from dg_manifests where repository_id = 12629;
+-----------+------------------------------------------------------+-----------------------+---------------+----------+
| id        | path                                                 | filename              | manifest_type | revision |
+-----------+------------------------------------------------------+-----------------------+---------------+----------+
|     13171 |                                                      | Gemfile               |             1 |      150 |
|  15497847 | railties/lib/rails/generators/rails/app/templates    | Gemfile               |             1 |        4 |
|  15800288 | railties/lib/rails/generators/rails/plugin/templates | Gemfile               |             1 |        1 |
|     12632 |                                                      | Gemfile.lock          |             2 |      306 |
|  15800286 |                                                      | rails.gemspec         |             3 |       23 |
|   6973553 | actioncable                                          | actioncable.gemspec   |             3 |       27 |
| 270055278 | actionmailbox                                        | actionmailbox.gemspec |             3 |        2 |
|   6964930 | actionmailer                                         | actionmailer.gemspec  |             3 |       26 |
|   6864194 | actionpack                                           | actionpack.gemspec    |             3 |       27 |
| 270055283 | actiontext                                           | actiontext.gemspec    |             3 |        2 |
|   6979354 | actionview                                           | actionview.gemspec    |             3 |       26 |
|   6829039 | activejob                                            | activejob.gemspec     |             3 |       25 |
|   6841847 | activemodel                                          | activemodel.gemspec   |             3 |       24 |
|   6975089 | activerecord                                         | activerecord.gemspec  |             3 |       28 |
|   6877665 | activestorage                                        | activestorage.gemspec |             3 |       32 |
|   6830351 | activesupport                                        | activesupport.gemspec |             3 |       53 |
|   6908551 | railties                                             | railties.gemspec      |             3 |       26 |
|   7013116 | railties/lib/rails/generators/rails/plugin/templates | %name%.gemspec        |             3 |        0 |
|  75961658 |                                                      | package.json          |             4 |        4 |
|  15800274 | actioncable                                          | package.json          |             4 |       22 |
| 270055280 | actiontext                                           | package.json          |             4 |        3 |
|  15800278 | actionview                                           | package.json          |             4 |       21 |
|  15800283 | activestorage                                        | package.json          |             4 |       21 |
|  15800284 | activestorage/test/dummy                             | package.json          |             4 |        2 |
|  15800287 | railties/lib/rails/generators/rails/app/templates    | package.json          |             4 |        2 |
| 110273770 |                                                      | yarn.lock             |            14 |        3 |
| 110273775 | actionmailbox/test/dummy                             | yarn.lock             |            14 |        1 |
| 110273784 | actiontext/test/dummy                                | yarn.lock             |            14 |        1 |
+-----------+------------------------------------------------------+-----------------------+---------------+----------+
```
</details>


### `dg_manifest_dependencies`

A row in this table corresponds to a single entry in a manifest file,
and represents a package-to-package dependency edge.

Some manifest files (e.g. `package.json`) list only direct edges,
whereas others (e.g. `package.lock`) include indirect dependencies too.
Clients must be aware of the package manager and file type to properly
interpret the semantics of an edge.

- **manifest_id** (Integer) The manifest file that describes the
    dependency (foreign key to `dg_manifests.id`).
- **requirements** (String) The version
    [requirements](#requirements-syntax) imposed on the imported
    package by the importer. (Note: not all entries conform to syntax.)
- **raw_requirements** (String) The version requirements expressed in the notation
    of the package manager.
- **exact_version** (String) The version number in SemVer notation,
    if `requirements` trivially denotes a single version.
    Contains occassional bad values (e.g. `1.3.0,~> 1.1`), apparently from
    manipulation of `requirements` under mistaken assumption that it
    is just a semver.
- **package_manager** (Integer) PackageManager enum; see `dg_packages.package_manager` for details.
- **package_name** (String) The name of the imported package.
   With `package_manager`, identifies the package in `dg_packages`.
- **scope** (Integer) Enum that represents whether the dependency is used at runtime or development ([Reference](https://github.com/github/dependency-graph-api/blob/41dc9cbbc4b3c1258f051090baee563f8ad25c20/app/models/types.rb#L13-L19)).
- **encoded_lower_bound** (BigInt) The least version that satisfies `requirements`,
    encoded in base 2<sup>16</sup>; see `dg_package_versions` for details.
- **encoded_upper_bound** (BigInt) Ditto, greatest version.
- **last_seen_at_revision** (Integer) The number of the last revision
    of the manifest file in which which this dependency was seen. If
    this doesn't match the revision of the associated manifest it
    means that the dependency is no longer present.
- **package_label** (String) Unused.

Size at Apr 2021: 8B rows, 2.5TB on disk.

Secondary indexes:
- manifest_id, package_name (unique)
- package_name (unique)
- package_name, encoded_lower_bound, encoded_upper_bound
- manifest_id, package_manager, package_name, exact_version

<details>
  <summary>Example: show current dependencies of Rails' main Gemfile (dg_manifest.id=13171)</summary>

```text
mysql> select package_name, requirements from dg_manifest_dependencies where manifest_id = 13171 limit 20;
+--------------------------------------+--------------+
| package_name                         | requirements |
+--------------------------------------+--------------+
| activerecord-jdbcmysql-adapter       | >= 1.3.0     |
| activerecord-jdbcpostgresql-adapter  | >= 1.3.0     |
| activerecord-jdbcsqlite3-adapter     | >= 1.3.0     |
| activerecord-oracle_enhanced-adapter | >= 0         |
| arel                                 | >= 0         |
| aws-sdk                              | ~> 2         |
| aws-sdk-s3                           | >= 0         |
| aws-sdk-sns                          | >= 0         |
| azure-storage                        | >= 0         |
| azure-storage-blob                   | >= 0         |
| backburner                           | >= 0         |
| bcrypt                               | ~> 3.1.11    |
| benchmark-ips                        | >= 0         |
| blade                                | >= 0         |
| blade-sauce_labs_plugin              | >= 0         |
| bootsnap                             | >= 1.4.4     |
| byebug                               | >= 0         |
| capybara                             | >= 3.26      |
| chromedriver-helper                  | >= 0         |
| coffee-rails                         | >= 0         |
+--------------------------------------+--------------+
```
</details>


### `dg_abstract_package_dependencies`

This table records the set of packages (`dependent_id`) that directly
depend on a given package, identified by (`package_manager`, `package_name`).

It appears to correspond closely to the count of Dependencies in the
[`Insights > Dependency Graph > Dependents`](https://github.com/rails/rails/network/dependents) UI.

- **dependent_id** (Integer) Identity of the importing package (foreign key to `dg_packages.id`).
- **package_manager** (Integer) PackageManager enum (see `dg_packages.package_manager`).
- **package_name** (String) The name of the imported package.
   With `package_manager`, identifies the imported package in `dg_packages`.

Size at Apr 2021: 19M rows, 5GB on disk.

Secondary indexes:
- package_name, dependent_id, package_manager (unique)
- dependent_id
- package_name, package_manager, id

<!--
Q. What are these dependencies, exactly?
Empirically, rows appears to represent direct dependencies.
For example, `Rails`, which has [thousands of
dependents](https://github.com/rails/rails/network/dependents)
(consumers), depends on `jruby/activerecord-jdbc-adapter`, which has
[fewer than a hundred dependents](https://github.com/jruby/activerecord-jdbc-adapter/network/dependents).
But perhaps it actually reports manifest edges, which may be direct or indirect
(see comment at top).
TODO: Verify experimentally.

When using Rails (package_manager, name) as the starting point, the
result corresponds to what we see in the UI: 13,000 consumers.
But if we ask: what (package_manager, name) pairs are related to the
dependent_id of rails (2066), we get only 17 items: see below.

I don't understand what this corresponds to in the user interface, as
Rails depends on a lot more than that, and the DG UI
[shows](https://github.com/rails/rails/network/dependencies) a lot
more than that.

mysql> select * from  dg_abstract_package_dependencies where dependent_id = 2066;
+------------+--------------+-----------------+------------------+---------------------+---------------------+
| id         | dependent_id | package_manager | package_name     | created_at          | updated_at          |
+------------+--------------+-----------------+------------------+---------------------+---------------------+
|       7424 |         2066 |               1 | actioncable      | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7425 |         2066 |               1 | actionmailer     | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7426 |         2066 |               1 | actionpack       | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7427 |         2066 |               1 | actionview       | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7428 |         2066 |               1 | actionwebservice | 2017-10-19 18:56:48 | 2018-03-29 02:28:36 |
|       7429 |         2066 |               1 | activejob        | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7430 |         2066 |               1 | activemodel      | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7431 |         2066 |               1 | activerecord     | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7432 |         2066 |               1 | activeresource   | 2017-10-19 18:56:48 | 2018-03-29 02:33:34 |
|       7433 |         2066 |               1 | activesupport    | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7434 |         2066 |               1 | bundler          | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7435 |         2066 |               1 | railties         | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|       7436 |         2066 |               1 | rake             | 2017-10-19 18:56:48 | 2018-03-29 02:32:33 |
|       7437 |         2066 |               1 | sprockets-rails  | 2017-10-19 18:56:48 | 2019-11-07 02:14:00 |
|  123735692 |         2066 |               1 | activestorage    | 2017-11-29 08:03:37 | 2019-11-07 02:14:00 |
| 3995253750 |         2066 |               1 | actionmailbox    | 2019-01-22 08:02:23 | 2019-11-07 02:14:00 |
| 3995253751 |         2066 |               1 | actiontext       | 2019-01-22 08:02:23 | 2019-11-07 02:14:00 |
+------------+--------------+-----------------+------------------+---------------------+---------------------+
-->

```
Q. Why the regrettable asymmetry in form of question and answer? It defeats self-joins.
```

<details>
  <summary>Example: count dependencies on Ruby Gem named 'rails'</summary>

```text
mysql> select count(dependent_id) from dg_abstract_package_dependencies where package_manager = 1 and package_name = 'rails'\G;
count(dependent_id): 13572
```
</details>

### `dg_abstract_package_dependency_counts`

Each row in this table records the approximate total number of
packages that depend on a specific package.
It is derived from `dg_abstract_package_dependencies` by `script/views/abstract_dependent_counts`.

- **package_manager** (Integer) PackageManager enum (see `dg_packages.package_manager`).
- **package_name** (String) Name of the package.
- **dependent_count** (Integer) Approximate total number of dependent packages.

### `dg_abstract_repository_dependencies`

Each row in this this table records a dependency from a repository to
a package, identified by (`package_manager, package_name`).

- **package_manager** (Integer) PackageManager enum (see `dg_packages.package_manager`).
- **package_name** (String) Name of the imported package.
- **repository_id** (Integer) Identity of the dependent repository
    (foreign key to `dg_repositories.id`).

Size at Apr 2021: 6B rows, 1.2TB on disk.

Secondary indexes:
- package_name, repository_id, package_manager (unique)
- repository_id
- package_name, package_manager, id

### `dg_abstract_repository_dependency_counts`

Each row in this table records the approximate total number of
repositories that depend on a specific package.
It is derived from `dg_abstract_repository_dependencies` by `script/views/abstract_dependent_counts`.

- **package_manager** (Integer) PackageManager enum (see `dg_packages.package_manager`).
- **package_name** (String) Name of the imported package.
- **dependent_count** (Integer) Approximate total number of dependent repositories.

Size at Apr 2021: 2M rows, 400MB on disk.

Secondary indexes:
- package_name, package_manager (unique)
- package_name

### `dg_checkpoints`

The checkpoints table records the last item processed on behalf of
various long-running or periodic jobs so they can resume (near) where
they left off after a restart.

- **name** (String) Name of the checkpoint. Uniquely indexed.
- **last_checkpointed_id** (BigInt) Number of last processed item.
   The meaning of "item" depends on the job.

The DG API server exposes a CRUD API to this table at the `/checkpoints` HTTP endpoint.

Secondary indexes:
- name (unique)

### `dg_star_counts`

The star counts table is used to gauge the popularity of a repository
when determining whether it is associated with a package.
The `star_count` is populated via GitHub's stargazers count on
manifest update and is thus an estimate.

- **github_repository_id** (Integer) identity of a GitHub repository. Uniquely indexed.
- **star_count** (Integer) Number of stars

Secondary indexes:
- github_repository_id (unique)


### Undocumented tables

```
mysql> select TABLE_NAME, TABLE_ROWS, DATA_LENGTH, INDEX_LENGTH
       from information_schema.TABLES
       where TABLE_NAME like 'dg_%'
       order by DATA_LENGTH + INDEX_LENGTH desc;
+------------------------------------------+-------------+---------------+---------------+
| TABLE_NAME                               | TABLE_ROWS  | DATA_LENGTH   | INDEX_LENGTH  |
+------------------------------------------+-------------+---------------+---------------+
| dg_dependency_specifications             |   314623952 |   32061259776 |   37612371968 |
| dg_package_release_dependent_counts      |    26474612 |    1952972800 |    2012545024 |
| dg_snapshots                             |     3407581 |     667942912 |     919289856 |
| dg_snapshot_blobs                        |     3629880 |  239809331200 |      48840704 | 250GB
| dg_abstract_package_dependency_counts    |      597074 |      33095680 |      35225600 |
| dg_package_release_vuln_counts           |       99875 |       9453568 |      14712832 |
| dg_dep_insights_backfills                |       66783 |       3670016 |       6258688 |
| dg_failed_manifest_messages              |      110284 |      29949952 |       3686400 |
| dg_vulnerable_version_ranges             |        5322 |       1589248 |        475136 |
| dg_key_values -- blocklists, etc.        |           3 |         16384 |         32768 |
| dg_builds                                |          41 |         16384 |         16384 |
| dg_build_types                           |          12 |         16384 |         16384 |
| dg_etl_imports                           |        1474 |        212992 |             0 |
| dg_schema_migrations                     |          84 |         16384 |             0 |
+------------------------------------------+-------------+---------------+---------------+
```

TODO: document these too, especially the big ones.

## "Requirements" syntax

A requirements string must conform to the `Requirements` production of the following grammar.

Grammar notation:
```
- lowercase and 'quoted' items are lexical tokens.
- Capitalized names denote grammar productions.
- (...) implies grouping.
- x | y means either x or y.
- [x] means x is optional.
- {x} means x is repeated zero or more times.
- The end of each declaration is marked with a period.
```

```
Requirements = Requirement {{' '} '||' {' '} Requirements}
             |
             .

Requirement = '=' {' '} semver
            | LowerBound ',' {' '} UpperBound
            | LowerBound
            | UpperBound
	    | '^'  {' '} semver
	    | '~>' {' '} semver
            .

LowerBound = ('>' | '>=') {' '} semver .
UpperBound = ('<' | '<=') {' '} semver .
```

The `semver` token is defined by the `<valid semver>` production
in the grammar at [SemVer v2.0.0](https://semver.org/).

The grammar was reverse engineered from the Ruby code and the database.
Spaces between tokens were made optional.

The database contains many entries that neither conform to this grammar
nor appear to be intentional, such as `,< 3.0.0` or `1.2.3 ||  || 2.3.4`,
likely the result of careless string manipulation and missing validation.

The `~>` operator (inherited from [Ruby Gems](https://guides.rubygems.org/patterns/))
matches versions equal to the specified one, or greater in the least significant digit.
For example: `"~> 1.2.3"` means `">= 1.2.3, < 1.3.0"`, and `"~> 1.2"` means `">= 1.2, < 2.0"`.
The `^` operator is apparently identical in meaning but uses the syntax of
[NPM](https://github.com/npm/node-semver#caret-ranges-123-025-004).

## Interacting with the data

Any process on the production network may access the data; there is
no authentication nor access control.

From a [production
shell](https://thehub.github.com/engineering/security/production-shell-access/#shell-and-other-applications), run the `gh-dbconsole` wrapper script:

```text
shell$ /data/github/shell/bin/gh-dbconsole dependency-graph dependency_graph
mysql>
```

(To access the GitHub `repositories` table, use `repositories` host
type in place of `dependency-graph`.)

The script is essentially equivalent to this `mysql` command:

```text
shell$ mysql -A -h db-mysql-dependency-graph-ro.service.github.net -u console_ro2 -p$MYSQL_CONSOLE_RO_PASS -P3306 dependency_graph
mysql>
```


Alternatively, you can access daily snapshots of the data using the
[Data warehouse
app](https://data.githubapp.com/sql/a0415ad0-e22a-4cea-afb8-3c95cbbe8896#!schemas-tab:hive.snapshots_presto.dependency_graph_dg_packages),
but this imposes a request [latency of around
8s](https://github.com/github/data-dot/issues/421) even for queries
that can be answered in a single disk seek, which makes interactive
exploration tedious.
