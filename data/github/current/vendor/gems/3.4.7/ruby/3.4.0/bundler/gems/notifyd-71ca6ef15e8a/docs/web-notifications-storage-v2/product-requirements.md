# Product Requirements

In order to make sure we support requirements from the product side we collected them
(see https://github.com/github/notifyd/issues/2465 for details) and decided on the following initial set of requirements to focus on.

**Note**: these requirements are considered to be initial constraints to start off from and not a frozen list. The expectation here
is that we will still change them later on and use the initial list as a starting point. We might also later decide that not all of these
features are part of the free plan.


| Feature	| Description	| Data Requirement	| Priority |
| ---     | ---         | ---               | ---      |
| Filter by reason	| filtering by notification reason | 	reason	| 1 |
| Filter by team mention | filtering by team that was mentioned (that the user is part of) | team mention | 1 |
| distinction between issues/PRs | basically supporting `is:issue` and `is:PR` | thread type | 1 |
| support general search syntax | i.e. what is listed in https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests | multiple | 1 |
| Grouping/Filtering by date range | show/group notifications by date | date | 2 |
| Grouping by repository | group notifications by repository | repository | 2 |
| Retrieve based on organization | include/exclude notifications for orgs based on SAML status | organization | 2 |
| Count based on filters | for any given filter we want to performantly get counts | multiple | 2 |
| Filter by subject  (title) | filter by subject (title) of a notification | subject | 3 |
| Additive filters | being able to filter by multiple values e.g. `repo:github/notifications repo:github/notifications-experience`  | multiple | 3 |
| Negative filters | negate any filter | multiple | 3 |
| Filter on thread state | filter on thread state properties like `is:closed` or `label:bug` | thread state | 4 |
| GHES support | this is here as a placeholder because I wasn't sure if it should be a product or system requirement | all | 4 |
| Full text search | full text search over the contents of notifications | multiple | 5 |
