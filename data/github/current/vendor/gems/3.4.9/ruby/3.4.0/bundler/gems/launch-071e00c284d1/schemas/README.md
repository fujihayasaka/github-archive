Launch Schemas
==============
Launch uses MySQL for persisting relational data.

MySQL schemas are maintained by https://github.com/skeema/skeema for development, testing, and production.
Skeema operates on `CREATE TABLE` syntax; we do not maintain a bunch of `ALTER TABLE`s like you may have seen in other systems.


Making database changes
=======================
1. Update whatever `*.sql` files are required for your change. `script/setup` and `script/test` will invoke skeema locally.
2. Submit schema changes along with code, following the normal PR process.
3. Once the code+schema PR has been approved by the Launch team, extract the `*.sql` changes out to a new PR. The new PR should _just_ be `schemas/**/*.sql` changes.
4. In the schema-only PR, request that `@github/database-infrastructure` execute the migration in production. Use a mention to summon the on-call database engineer.
5. Ping #databases on Slack; humans there are great at providing a timeline for when the migration will be executed.
6. Once the migration has been performed, merge the schema-only PR change.
7. Merge master, so the original code+schema PR includes only code changes.
8. Deploy the remaining (code-only) PR per normal procedure.

