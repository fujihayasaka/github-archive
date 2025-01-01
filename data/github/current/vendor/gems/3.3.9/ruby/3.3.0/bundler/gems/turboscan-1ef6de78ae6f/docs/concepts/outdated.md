# Outdated

## What does it mean?

Outdated is the name we are using to describe *configurations* that are no longer relevent, normally because a user has decided a configuration will no longer receive any new analyses.

## How does it work?

A marker analysis is created with no results (synthetically, not by an actual analysis with a tool), which in turn marks all alerts for the associated configuration as fixed, and ensures that the configuration is no longer in the list of expected PR checks.
For an analysis to mark a configuration as outdated, it must also be the tip (the analysis flagged as `most_recent`) for the configuration.
At the time of writing, this process is kicked off when Turboscan receives a special tombstone delivery via the New Analysis Hydro topic.

If a further analysis is received for an outdated configuration, it will have set the outdated analysis as its baseline (just like any new analyis sets the previous as its baseline). Any "fixed" alerts due to being marked as outdated may be re-opened and the configuration will be active again (a similar undo effect can also be achieved by deleting the outdated analysis).
As long as the `most_recent` analysis is not flagged as outdated, the configuration is considered active.

## How do we represent it in the database?

### `ts_analyses`

The `ts_analyses` table is the canonical reference for whether a configuration is outdated.
To be outdated an analysis must have the following values:

* `most_recent` is `true`
* `is_outdated` is `true`

Technically `is_outdated` is actually denormalised from the `ts_deliveries` table, and it would be possible to derive it by doing a join on the most recent analysis and its related delivery, but this is not practical in all circumstances.

### `ts_deliveries`

Deliveries are how we represent the intention to set a configuration as outdated.
There are times when a configuration is already outdated, or never had a successful run, but in all scenarios there is a delivery with the intended configuration values set, even if it is considered failed:

* `outdated_config_category`
* `outdated_config_tool_name`

The `ts_analysis` table is the canonical place for marking as outdated, because without knowing if the related analysis is a tip (`most_recent` is `true)` it is not possible to determine if a configuration is actually outdated or not.

## Why is it needed?

In Turboscan the concept of a configuration is slightly vague.
There is no table where configurations are defined, rather they are a table constraint on `ts_analyses` we use to determine when a new analysis should be considered the next one in a series of analyses or if it is a part of a totally separate group of analyses.
The problem with this is that if an analysis is received with a different configuration (due to a change in category name or something similar), when it is, in real terms, a continuation of an existing configuration, you end up with a *stale tip* that is no longer receiving new analyses.
The two main symptoms of this are:

* An old configuration showing up as an expected PR check that is missing.
* Alerts remaining open because they are only fixed in a new configuration, but still open in a stale one.

To combat these issues, we came up with outdated.
When a user marks a configuration as outdated they no longer see:

* stale alerts
* incorrectly expected checks for stale tips
* stale tips showing up on the tool status page
* permanently failed configurations showing up on the tool status page

## Why is it called "delete configuration" in the UI?

This was ultimately a product decision, to describe this feature in the most simple terms.
It is a very soft form of deletion in some senses and does make some things stop showing up, but from a techincal standpoint this labelling is probably misleading.

### Glossary

*Configuration*: The unique combination of repository ID, ref, tool and category to distinguish analyses from each other.
*Stale Tip*: A most recent analysis from a configuration that is no longer in-use.
*Stale Alert*: An alert that stems from a configuration that is no longer in-use, and if it is in an open state, can be effectively un-closeable.

### Related Links

- [ADR](https://github.com/github/code-scanning/blob/main/docs/adrs/0031-resolving-stale-alerts.md)
- ["deleting" stale configurations demo](https://github.rewatch.com/video/edvl5lu6u6d2a48o-deleting-stale-code-scanning-configurations-demo)
- [Stale Tips solution discussion](https://github.rewatch.com/video/e3yh9yww9b5xo9lq-stale-tips-solution-discussion)
- [Blog post announcement](https://github.blog/changelog/2023-03-10-delete-stale-code-scanning-configurations-to-close-outdated-alerts/)
- [User Docs](https://docs.github.com/en/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/managing-code-scanning-alerts-for-your-repository#removing-stale-configurations-and-alerts-from-a-branch)
