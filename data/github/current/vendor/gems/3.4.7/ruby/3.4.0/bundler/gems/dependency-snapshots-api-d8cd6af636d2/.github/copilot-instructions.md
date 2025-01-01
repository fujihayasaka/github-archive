# Review glossary

The glossary in docs/glossary.md provides official definitions for terms used in the dependency-snapshots-api. It includes key concepts such as "snapshot," "manifest," "dependency," and "canonical snapshot," along with their relationships and significance within the service. Refer to this file for a comprehensive understanding of the terminology used in the API documentation and codebase.

# Two environments

This service runs in two environments: GHES and cloud.

Cloud:
- Snapshot blobs are stored in Azure Blob Storage.
- All snapshots are retained indefinitely.

GHES:
- Snapshot blobs are stored in the database.
- Historical snapshots are discarded immediately.
- Snapshots for branches other than the default branch are discarded immediately.
- Feature flags are not available in GHES.

Features and tests will need to respect these differences.

# Feature guidelines

It is important to use feature flags to reduce risk in production. Whenever a change goes beyond the level of a simple bug fix, it should be behind a feature flag. Note that features gated behind feature flags are not available in GHES, so feature flags should be removed once the feature is stable and no longer needs to be toggled.

# Testing guidelines

It is extremely important to include tests for any new functionality. A failing test should be created and run before the implementation is written (red-green). Do not trust a test if you haven't seen it fail.

Tests should focus on readability. Use helpers, descriptive names, comments, and custom failure messages.

Unit tests are preferred. We also have integration tests in `integration_test.go`, and these run in a more realistic environment, but they are less flexible and it is impossible to use mocking and spies in the integration tests.

# Working on issues

When given an issue to work on, please follow these steps:
1. Read the issue carefully and make sure you understand it. Use the glossary to clarify any terms you are unfamiliar with.
2. Ask clarifying questions if needed. If the issue goes beyond a simple bug fix, it is likely that clarifying questions will help both you and the user to understand the issue better.
3. Create a failing test for the issue. Run the test to verify that it fails. The failure message should be clear and match expectations for the issue.
4. Describe your proposed approach to solving the issue. Get feedback from the user on your approach. This is especially important for complex issues or new features.
5. Favor making changes one at a time, getting verification from the user that the change is correct and makes sense.
6. Once the solution is implemented, run all tests to verify that they pass. If any tests fail, describe the failure to the user and get feedback on how to proceed.
7. When the change is complete, recommend a pull request body to the user. Review `.github/pull_request_template.md` for guidance on what to include in the pull request body.
