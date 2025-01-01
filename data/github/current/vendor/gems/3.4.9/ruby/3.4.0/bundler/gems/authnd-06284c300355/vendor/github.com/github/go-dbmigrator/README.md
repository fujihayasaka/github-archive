> With the recent reorg, `Frameworks-Containers` team has been dissolved. Starting from 5th June 2023, we are part of Ecosystem-Events team. We continue to own and provide support for the charter owned by the `Frameworks-Containers` team, but we are not working on any new feature developments.

# go-dbmigrator [![GoDoc](https://pkg.go.dev/badge/github.com/github/docs)](https://gopkgs.githubapp.com/github.com/github/go-dbmigrator)

This project is a work-in-progress attempt at standardizing a solution for database migrations (and possibly transitions) for Go services at GitHub that are also part of GitHub Enterprise (GHE).

It is initially a port of code written for the [launch service](https://github.com/github/launch) from our very own @iheanyi!

It wraps [golang-migrate's migrate](https://github.com/golang-migrate/migrate) package, which provides some file generation and glue around the migration operation.

Also, note that this package concerns only GHE migrations and transitions, and cloud transitions. [skeefree](https://github.com/github/skeefree) is used for cloud migrations. Perhaps this will be better expressed in a chart:

_ | For Database | Cloud | GHE |
--- | --- | --- | ---      |
Development Migrations | MySql | `skeema` used locally | `skeema` used locally |
Development Transitions | MySql | `go-dbmigrator` used locally | `go-dbmigrator` used locally |
Production Migrations | MySql| Skeefree | `go-dbmigrator` |
Production Transitions | MySql| `go-dbmigrator` via Moda jobs | `go-dbmigrator` |
Dev or Pro Migrations | SQL Server | Not Used | migrations docker container |
Dev or Pro Transitions | SQL Server | Not Used | migrations docker container |

The `go-dbmigrator` project support **MySql** and **MS SQL Server** migrations. **MySql** is supported with the `go-dbmigrator` binary while **SQL Server** is supported with `migrations` container image. These techniques may converge over time.

You can learn more about each and thier usage in the following docs:

* [Using migrations for MySql](docs/MySql.md)
* [Using migrations for MS SQL Server](docs/SQLServer.md)

## Contributing :tada:

We welcome all changes and help on improving this project. Please submit your pull request and ask for reviews in the [`#frameworks-containers`](https://github.slack.com/archives/CS6DA6Y5R) slack channel or just open an issue to start work. For development we also [have this guide](docs/DEVELOPMENT.md) that you can follow to help you get better oriented.

## Contributing

 To learn more about developing and making updates to this repo, please checkout [the contributing guide](docs/CONTRIBUTING.md).
