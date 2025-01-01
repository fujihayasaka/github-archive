# Database Migrations in Production with Skeema

The database schema and migrations for Production Trust-Metadata-API is managed by [skeefree](https://github.com/github/skeefree).

For more technical information on how it works, see [Skeefree - How Skeefree Works](https://github.com/github/skeefree/blob/master/docs/how.md).

## Making Production Schema Changes

1. Run the migrations and skeema commands locally: `make dev-migrate-up`
1. Confirm the changes look correct: you should see changes to files in `db/schema/*.sql`
1. Commit changes and create a Pull Request in the [Trust-Metadata-API](https://github.com/github/trust-metadata-api) repository
1. Request a review from `@github/package-security-reviewers` team members
1. The `skeema-diff` Action will analyze the changes.
1. Once the PR is approved, add the `migration:for:review` label to the PR.
1. `skeefree` will run and generate migration commands
1. `skeefree` will then request a review from `@github/database-infrastructure`
1. A `@github/database-infrastructure` member needs to approve the PR
1. Once approved by `@github/database-infrastructure`, `skeefree` will automatically run the migration and comment as needed
1. When all the migrations are complete, `skeefree` `@-mentions` the developer with instructions to deploy/merge.
