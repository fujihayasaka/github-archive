# Package manager adapters

Package manager adapters run in docker containers and publish package release information to the dependency graph.

### Running an adapter

- Run adapters with `script/run <adapter>`.
- Run tests with `script/test <adapter>`.

### Adding an adapter

#### Generate a scaffold

To add a new package manager adapter, generate a scaffold with `script/generate <adapter>`. For example, to generate a scaffold for `npm`, run `script/generate npm`.

Next, modify the `Dockerfile` to install dependencies and copy source files.

```console
$ cat Dockerfile
FROM node:7

COPY package.json .
RUN npm install
COPY main.js .

ENTRYPOINT ["./wrapper"]
```

Finally, modify the wrapper script to properly invoke your adapter and your adapter's tests.

```console
$ cat wrapper
#!/bin/bash

usage() {
  echo "Usage: $0 {run|test}"
}

case "$1" in
  run)
    node main.js
    ;;
  test)
    npm test -- --recursive
    ;;
  console)
    /bin/bash
    ;;
  *)
    usage
    exit 1
esac
```

#### Publishing data

Adapters can publish data by `POST`ing JSON payloads to the dependency graph `/package_releases` endpoint. The dependency graph host is injected into the container via the `SINK_PROXY_URL` environment variable. JSON payloads must adhere to the following schema:

TODO(adonovan): move this documentation into the [authoritative definition](https://github.com/github/hydro-schemas/blob/master/proto/hydro/schemas/github/dependencygraph/v0/package_release.proto), and link to it. See https://github.com/github/dependency-graph-api/issues/1928.

```json5
{
  // Required: The exact name of the package manager as listed in `types.rb`
  package_manager: STRING,

  // Required: The name of the package
  package_name: STRING,

  // Required: The package release version
  // The interpretation of the version depends on the package manager.
  version: STRING,

  // Optional: Some package managers scope package names within a namespace
  namespace: STRING,

  // Optional: The package description
  description: STRING,

  // Optional: The package author or authors
  authors: STRING,

  // Optional: The number of package downloads (if available)
  download_count: INTEGER,

  // Optional: The third-party package host identifier for this package (if available)
  external_id: STRING,

  // Optional: The URL that hosts package source code, hopefully a github.com URL :)
  source_url: URL,

  // Optional: The URL that hosts the package homepage
  home_url: URL,

  // Optional: The URL that hosts the package docs
  docs_url: URL,

  // Optional: The UNIX timestamp of when the package release was published
  published_at: INTEGER,

  // Optional: The UNIX timestamp of when the package release was pulled
  unpublished_at: INTEGER,

  // Optional: The UNIX timestamp of when the package release was built (if available)
  built_at: INTEGER,

  // Optional: An array of package release dependencies
  dependencies: [
    {
      // Required: The name of dependency package
      package_name: STRING,

      // Required: The dependency requirements e.g. '>= 1.2.0'
      // The interpretation of the requirement depends on the package manager.
      requirements: STRING,

      // Optional: "runtime" or "development", defaults to "runtime"
      scope: STRING
    }
  ]
}
```
