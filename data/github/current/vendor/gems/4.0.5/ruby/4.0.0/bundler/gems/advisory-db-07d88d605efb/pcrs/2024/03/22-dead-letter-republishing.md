<!--

Thank you for filling out a production change request (PCR)!

Production Change Records are necessary to document changes to production
other than code changes. This allows the team to review and audit changes
that cannot be otherwise tracked via repository history.

For github/advisory-db, this includes:

* rails console changes
* kubectl changes
* --- other examples here ---

When ready, save your PCR in a file with the naming convention:

  pcrs/YYYY/MM/DD-<title>.md

-->

# *2024-03-22* *Republishing dead letter queue advisories*

**Primary:** @sarahkemi

**Deployment Partner:** TBD

## Status

This PCR is available for full review before any steps are taken to modify
production.

## Context

As part of our First Responder flow we now try to address and resolve advisories that were dropped when trying to consume and process their hydro message via the `SubmitAdvisoryProcessor`. This week there are two advisories in the DLQ, `GHSA-4pwp-cx67-5cpx` and `GHSA-33m6-q9v5-62r7`.

Both advisories were successfully stored in our repository but were not able to be processed in dotcom for the following reasons:
- GHSA-4pwp-cx67-5cpx was not able to be stored given that the version of `cvss-suite` we were using in dotcom was very old and did not consider the advisory's CVSS valid
- GHSA-33m6-q9v5-62r7 was not able to be stored given that the one of the vulnerable version range's requirement strings was 77 characters, while our character limit on that column at the time was 75.

Both issues have been resolved in https://github.com/github/github/pull/317967 and https://github.com/github/github/pull/317976.

### Risk Assessment

<!-- Please select from one of the following and detail why this level was chosen -->

- [ ] **Low risk** the modifications are small, highly observable, and easily rolled back.

### Affected services

`github/advisory_database`

## Production Change Steps

<!--
Describe, in detail, which steps will be made. Include risks involved,
rollback plans, and how you will observe the change in production.

Describe exactly which steps will be run, and where. List all chatops,
link all stafftools pages, list all shell commands to be run. Wherever
possible, avoid running multiple commands and instead deploy an executable
script to production via a tested and reviewed pull request, then list the
one-liner execution of that script here.

For each step, what observations do you need to make to be sure the change
was completed successfully? If there are any risks, then how will you
confirm the risks were avoided or occurred?

At each step, describe the process to un-do that step. How long will it
take for each step to be reflected in production?
-->

1. Go to advisory-db console to perform the following commands (`gh-k8s-shell -n advisory-db-production script/console`)

```ruby
a1 = Advisory.find_by(ghsa_id: "GHSA-4pwp-cx67-5cpx")
a2 = Advisory.find_by(ghsa_id: "GHSA-33m6-q9v5-62r7")
PublishAdvisoryToHydroJob.perform_now(a1)
PublishAdvisoryToHydroJob.perform_now(a2)
```

2. Check that both advisories are now accessible on dotcom

- https://github.com/advisories/GHSA-4pwp-cx67-5cpx
- https://github.com/advisories/GHSA-33m6-q9v5-62r7

3. [Shift offset](https://hydro.githubapp.com/kafka/clusters/potomac/consumer_group?group_id=advisory_db&tab=reset-offsets) on `cp1-iad.ingest.advisory_db.v0.SubmitAdvisory.DeadLetter` to skip over the now resolved dead letters.

## Safe Deployment Checklist

Here are the answers to the [Safe Deployment Checklist](https://thehub.github.com/epd/engineering/dev-practicals/service-lifecycle/safe-deployment-checklist/#safe-deployment-checklist),
including justifications for why some may not apply.

<!--
Many of the answers here should be answered by the previous section.

Refer to numbered steps above as appropriate.
-->

### Have you tested this change before production?

No because there's not a straightforward way to do this end-to-end testing and it is fairly low stakes

### Where will this change roll out to when it deploys (canary / production / other)?

Production

### Is this change behind a feature flag? (if not, why can't it be feature flagged)?

Nope, publishing hydro messages

### How will you know when this change is rolled out and what its impact is? Do you have metrics you can watch?

Visiting the links ensures that we've successfully submitted those advisories

### Does this change potentially increase load on a database or other dependencies?

No

### How will you roll this change back if something goes wrong? How long will it take to roll the change back? How many customers will be impacted? Do you have a playbook for this rollback?

There is really no rollback but the message just would fail again and we'd have to figure out another solution and attempt once more.


## Previous deployment patterns

- https://github.com/github/team-advisory-database/blob/main/docs/runbooks/handling-missed-hydro-advisory-updates.md
