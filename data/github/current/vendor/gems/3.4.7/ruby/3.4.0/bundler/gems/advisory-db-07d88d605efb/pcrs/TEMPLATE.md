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

# *YYYY-MM-DD*. *Title of the PCR*

**Primary:** @...
**Deployment Partner:** @...

## Status

<!-- Include one of the following statements: -->

This PCR is available for full review before any steps are taken to modify
production.

This PCR contains initial steps for full review, but more steps will
require discovering information in the system after those first steps.

This PCR contains a log of the steps taken while mitigating an active
incident. The steps are described for posterity and post-mortem review.

<!-- If the change was rolled back or caused in incident, please include the relevant information here -->

## Context

<!-- Describe why the production change is required. -->

### Risk Assessment

<!-- Please select from one of the following and detail why this level was chosen -->

- [ ] **Low risk** the modifications are small, highly observable, and easily rolled back.
- [ ] **Medium risk** changes that are isolated, reduced in scope or could impact few users and not bring the site down.
- [ ] **High risk** changes are those that could impact our customers and SLOs, low or no test coverage, low observability, or slow to rollback.

### Affected services

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

1. _Step one_

0. _Step two_

0. _Step three_

## Safe Deployment Checklist

Here are the answers to the [Safe Deployment Checklist](https://thehub.github.com/epd/engineering/dev-practicals/service-lifecycle/safe-deployment-checklist/#safe-deployment-checklist),
including justifications for why some may not apply.

<!--
Many of the answers here should be answered by the previous section.

Refer to numbered steps above as appropriate.
-->

### Have you tested this change before production?

_TODO_

### Where will this change roll out to when it deploys (canary / production / other)?

_TODO_

### Is this change behind a feature flag? (if not, why can't it be feature flagged)?

_TODO_

### How will you know when this change is rolled out and what its impact is? Do you have metrics you can watch?

_TODO_

### Does this change potentially increase load on a database or other dependencies?

_TODO_

### Do you have a plan for monitoring any load increase and turning the change off if it reaches a certain threshold?

_TODO_

### If this change could cause a high severity outage, do you have paging alerts for monitoring thresholds so you can roll it back before that happens?

_TODO_

### Can you optimize this change to reduce load?

_TODO_

### How will you roll this change back if something goes wrong? How long will it take to roll the change back? How many customers will be impacted? Do you have a playbook for this rollback?

_TODO_

### What's the worst thing that could happen with this change? How will you deal with it if that thing happens?

_TODO_

### Did you communicate this change with a planned event?

_TODO_

### If this change impacts other services or infrastructure, have you communicated with that team to understand what the impact will be?

_TODO_

### If you're making an architectural change, have you tested it on a smaller scale? Have you consulted experts in those architecture areas?

_TODO_

### Who are you pairing with to make sure you don't make a mistake when rolling out this change?

**Deployment partner:** @...

## Previous deployment patterns

<!--
If they exist, please link to existing PCRs, playbooks, documentation, or
issues that describes similar situations to your deployment plan.

* _Previous PCR..._
* _Existing playbook..._
* _Issue where we did something similar but didn't use PCRs yet_
-->
