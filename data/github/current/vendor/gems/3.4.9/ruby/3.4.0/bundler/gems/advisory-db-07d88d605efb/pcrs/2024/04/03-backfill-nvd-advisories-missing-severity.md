# *2024-04-03*. *Backfill NVD Advisories that are Missing Severity*

**Primary:** @rebelagentm
**Deployment Partner:** @rthorpeii

## Status

This PCR is available for full review before any steps are taken to modify
production.

## Context

[It was discovered](https://github.com/github/team-advisory-database/issues/4135) that some auto-published NVD Advisories were missing severity and/or CVSS data.  Many of these happened due to an incorrect state due to a bulk-closing bug.  The other Advisories ended up this way due to older tooling and the Advisories not getting backfilled after we introduced auto-publishing.

### Risk Assessment

- [x] **Low risk** the modifications are small, highly observable, and easily rolled back.

### Affected services

- Advisory Inbox

## Production Change Steps

1. We'll start by running the backfill on a small number Advisories to ensure things work and that we're not impacting Curation queues before proceeding to larger batches

2. Run `BackfillMissingSeveritiesJob.perform_later(limit=10)`

3. Run `BackfillMissingSeveritiesJob.perform_later(limit=100)`

4. Run `BackfillMissingSeveritiesJob.perform_later(limit=1000)`

5. Run `BackfillMissingSeveritiesJob.perform_later` to finish backfilling the rest of the Advisories

## Safe Deployment Checklist

Here are the answers to the [Safe Deployment Checklist](https://thehub.github.com/epd/engineering/dev-practicals/service-lifecycle/safe-deployment-checklist/#safe-deployment-checklist),
including justifications for why some may not apply.

### Have you tested this change before production?

Yes.  [Some manual testing](https://github.slack.com/archives/C019G8L19DZ/p1709321782222109) was done.  We'll also start the backfill with a small number of Advisories before proceeding to larger batches.

### Where will this change roll out to when it deploys (canary / production / other)?

The [PR](https://github.com/github/advisory-db/pull/2328) to enable the job will be rolled out to Production.  Kicking off the backfill job will be done in a Production console.

### Is this change behind a feature flag? (if not, why can't it be feature flagged)?

No.  The deployed code is a job that must be manually started.

### How will you know when this change is rolled out and what its impact is? Do you have metrics you can watch?

Following standard Production deployment steps.  Standard monitoring will be watched.

### Does this change potentially increase load on a database or other dependencies?

Yes.

### Do you have a plan for monitoring any load increase and turning the change off if it reaches a certain threshold?

We can stop the running job if need be.

### If this change could cause a high severity outage, do you have paging alerts for monitoring thresholds so you can roll it back before that happens?

We do not have paging alerts, but we can restart/redeploy the app if necessary.

### Can you optimize this change to reduce load?

Yes.

### How will you roll this change back if something goes wrong? How long will it take to roll the change back? How many customers will be impacted? Do you have a playbook for this rollback?

The [PR](https://github.com/github/advisory-db/pull/2328) can be rolled back using standard rollback procedure.  However, the PR itself should not cause any problems as it's code changes require being used manually.

Rollbacks and deployments for Advisory Inbox typically take 10 minutes or less.

This would be unlikely to affect customers.

There is not a playbook for reverting data should something go wrong.

### What's the worst thing that could happen with this change? How will you deal with it if that thing happens?

Advisory data ends up incorrect.  Correcting that would depend on what data is wrong and would require investigation.

### Did you communicate this change with a planned event?

No.

### If this change impacts other services or infrastructure, have you communicated with that team to understand what the impact will be?

We will announce this to the Curation team before we kick it off.

### If you're making an architectural change, have you tested it on a smaller scale? Have you consulted experts in those architecture areas?

N/A

### Who are you pairing with to make sure you don't make a mistake when rolling out this change?

**Deployment partner:** @rthorpeii

## Previous deployment patterns

N/A
