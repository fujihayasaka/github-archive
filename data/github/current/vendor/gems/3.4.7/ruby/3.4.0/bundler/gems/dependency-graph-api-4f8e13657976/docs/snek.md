# Snek Outside-In Test Suite

## Overview
The [Snek test suite](https://github.com/github/snek) is an outside-in UI test framework built on top of [Playwright](https://playwright.dev/). The framework performs headless browser tests against UI features in a realistic manner. For dotcom tests, these are performed against the "live" production-deployed site. In enterprise environments, the tests can be wrapped in utility code to generate ephemeral users/orgs and repositories (including content injection) which can then be cleaned up as part of each execution.

The main components of Snek that end users need to know about are:
- The **Page implementations**: these teach the Snek runner how to navigate, interact with, and harvest UI data from site components under test.
    - Repository Insights Dependencies tab: [page](https://github.com/dsp-testing/dependency-graph-snek-test/network/dependencies) [code](https://github.com/github/snek/blob/main/e2e/pages/repoDependenciesPage.ts)
    - Repository Insights Dependents tab: [page](https://github.com/dsp-testing/dependency-graph-snek-test/network/dependents) [code](https://github.com/github/snek/blob/main/e2e/pages/repoDependentsPage.ts)
    - Org Insights page Dependencies tab (package and repo): [page](https://github.com/orgs/dsp-testing/insights/dependencies) [code](https://github.com/github/snek/blob/main/e2e/pages/orgDependenciesPage.ts) _note: unused for now (see below)_
- The **Feature tests**: these utilize the Page implementations to actual interact with the site components under test, and evaluate results against expectations.
    - Repository Insights Dependencies test: [code](https://github.com/github/snek/blob/main/e2e/repositoryInsightsDependencyGraph-dependencies.spec.ts)
    - Repository Insights Dependents test: [code](https://github.com/github/snek/blob/main/e2e/repositoryInsightsDependencyGraph-dependents.spec.ts)
- The **Snek runner environment file**: applies environment-based configuration and overrides to your test runs while working in local dev env [example](https://github.com/github/snek/blob/main/.env.example)
- The **documentation**: this is WIP/changing rapidly at the moment due to the recent test runner rewrite. Keep an eye on the latest updates [here](https://github.com/github/snek/tree/main/docs)

## Local dev
1. Clone the repo [link](https://github.com/github/snek)
2. Obtain Vault creds for the `snek-testing-bot` and follow setup steps [here](https://github.com/github/snek/blob/main/docs/setup.md)
3. Populate and export env vars illustrated in the doc (and the `.env.example` file) to taste:
   - Fill in bot credentials as local exported env vars to run feature tests against production-deployed dotcom env
   - To run feature tests against `github.localhost` only:
       a. Set up DG-API and `github.localhost` (or dotcom Codespace) [link](https://github.com/github/dependency-graph-api#running-dotcom--dg-api)
       b. Set `monalisa` user/pass in Snek env vars
       c. Log into `github.localhost` as `monalisa` and set up 2FA
       d. Instead of using the 2FA QR code to configure, click the text link, capture the token string
       e. Set `GITHUB_FEATURE_TOTP` in your local env with the token string
4. `npm test` (sanity check Snek code)
5. `npx playwright test` (execute feature tests against target env)

## Updating the tests
The DG feature tests utilize `data-test-id` HTML attributes to future proof the `Page` implemnetation selectors against UI changes. However, at times feature changes such as newly supported ecosystems or new data surfaced on the Insights pages will break the suite. When this happens, or if you proactively decide to augment the feature tests with new manifests and dependencies, you'll need to update the Snek feature tests or the static test repos we use to populate the Insights pages the feature tests execute against.

### Add A Dependency
1. Add a new manifest to the [dotcom test repo](https://github.com/dsp-testing/dependency-graph-snek-test)
2. Update the [repo Insights Dependencies test](https://github.com/github/snek/blob/main/e2e/repositoryInsightsDependencyGraph-dependencies.spec.ts) expectations

### Add a Dependent
1. Add and/or publish a new package in the [dotcom test repo](https://github.com/dsp-testing/dependency-graph-snek-test) (requirements are ecosystem dependent)
2. Declare a dependency on the new package in the [dotcom dependent test repo](https://github.com/dsp-testing/dependency-graph-snek-test-dependent)
3. Update the [repo Insights Dependents test](https://github.com/github/snek/blob/main/e2e/repositoryInsightsDependencyGraph-dependents.spec.ts) expectations

### Add Org Insights Test
1. Setup an Enterprise test org in an appropriate dotcom env (consult product and [Snek team](https://github.com/orgs/github/teams/snek-reviewers/members) for guidance)
2. Apply `owner` role to the `snek-testing-bot` and `snek-testing-bot-dev` accounts (see step 1!)
3. Add a feature test (using the new runner) and the [org Insights Page implementation](https://github.com/github/snek/blob/main/e2e/pages/orgDependenciesPage.ts)

Due to concerns about making Snek bots owners of the `dsp-testing` Enterprise org, the [org Insights test](https://github.com/github/snek/pull/442/commits/0b8a294883285d188d33b3a2f2b214dba947fadc) written for the original Snek runner didn't ship with the original round of repo Insights tests. Updates (and less granular expectation checks) should be applied to this base, if used. Note the use of the `data-test-id` HTML attributes in the org Insights `Page` implementaion.

## Snek + DG for Enterprise
After consulting the [Snek team](https://github.com/orgs/github/teams/snek-reviewers/members), expanding the DG Snek test suite to support Enterprise environments was deemed blocked for this quarter. Once GH Connect is removed and GHEX-env DG features are configured and enabled by default we can proceed to add them. The Snek team is independently looking at support for setup prerequisites as well. The tracking issue for this follow on work is [here](https://github.com/github/dependency-graph/issues/467).

