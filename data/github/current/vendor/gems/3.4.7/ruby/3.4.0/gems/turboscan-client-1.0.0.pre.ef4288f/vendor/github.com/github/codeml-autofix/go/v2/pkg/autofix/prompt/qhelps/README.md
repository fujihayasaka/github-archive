By default, autofix suggestions for CodeQL alerts are generated using the standard query help for each supported CodeQL query (published to https://codeql.github.com/codeql-query-help) as part of the prompt, and the prompt template is language-independent. We make improvements over time to the query help to ensure good quality of autofix suggestions.

This folder contains query help "overrides": improvements that have not yet been merged upstream into the standard query help, or are missing from older versions of query packs used in our internal testing.

At the time of writing, all existing overrides have been published upstream, so these overrides are used when testing older query packs but have no effect in production.

Do not delete the `js-dont-delete.md` since it is used in tests.
