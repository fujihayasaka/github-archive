<!--

Thank you for filling out a production change request (PCR)!

Production Change Records are necessary to document changes to production
other than code changes. This allows the team to review and audit changes
that cannot be otherwise tracked via repository history.

For github/github, this includes:

* rails console changes
* kubectl changes
* --- other examples here ---

When ready, save your PCR in a file with the naming convention:

  pcrs/YYYY/MM/DD-<title>.md

-->

# *2023-07-28*. *Backfill local advisory DB with Swift advisories*

- **Primary:** @jurre 
- **Deployment Partner:** @deivid-rodriguez

## Status

<!-- Include one of the following statements: -->

This PCR is available for full review before any steps are taken to modify
production.

<!-- If the change was rolled back or caused in incident, please include the relevant information here -->

## Context

We have recently added support for ingesting new Swift advisories into our local
DB of advisories, which we use to make sure we never propose security updates to
versions vulnerable to _any_ advisory.

However, we still need to backfill our DB with Swift advisories published before
we added support.

This is documented as one step for being able to support security updates for an
ecosystem at
https://github.com/github/dependabot-updates/blob/5115ab5b0f9f84ddaf43a4d5517812645578d09c/docs/development/security-updates/adding-a-new-ecosystem.md#1-dependabot-needs-to-consume-the-new-advisories
(step 3).

<!-- Describe why the production change is required. -->

### Risk Assessment

<!-- Please select from one of the following and detail why this level was chosen -->

- [x] **Low risk** the modifications are small, highly observable, and easily rolled back.
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

1. SSH into ops-shell: `ssh shell`

0. Sign into vault `. vault-login`

0. Open a production rails console to dependabot-api: `gh-k8s-shell -n dependabot-api-production bin/rails console`

0. Check how many are to be imported:
   ```ruby
   GitHubSecurityAdvisory::SkippedAdvisories.warning(ecosystem: "swift").count
   ```

0. (Optional) Inspect the GHSA ids to import:
   ```ruby
   GitHubSecurityAdvisory::SkippedAdvisories.warning(ecosystem: "swift").list
   ```

0. Import the missing advisories:
   ```ruby
   GitHubSecurityAdvisory::SkippedAdvisories.warning(ecosystem: "swift").retry_all
   ```

## Safe Deployment Checklist

Here are the answers to the [Safe Deployment Checklist](https://thehub.github.com/epd/engineering/dev-practicals/service-lifecycle/safe-deployment-checklist/#safe-deployment-checklist),
including justifications for why some may not apply.

<!--
Many of the answers here should be answered by the previous section.

Refer to numbered steps above as appropriate.
-->

### Have you tested this change before production?

No, but we have executed them in the past for other ecosystems.

### Where will this change roll out to when it deploys (canary / production / other)?

Production.

### Is this change behind a feature flag? (if not, why can't it be feature flagged)?

No. I'm not sure how feature flagging this would look. I guess importing a
single missing advisory first?

### How will you know when this change is rolled out and what it's impact is? Do you have metrics you can watch?

The
[dependabot-api/missed-advisory-changes](https://app.datadoghq.com/monitors/37743419?from_ts=1690477139000&to_ts=1690478339000&source=monitor_notif&eval_ts=1690478339000)
monitor should get back to OK.

### Does this change potentially increase load on a database or other dependencies?

I think there's only one advisory missing, so extra load should not be noticiable?

### Do you have a plan for monitoring any load increase and turning the change off if it reaches a certain threshold?

N/A

### If this change could cause a high severity outage, do you have paging alerts for monitoring thresholds so you can roll it back before that happens?

N/A

### Can you optimize this change to reduce load?

N/A

### How will you roll this change back if something goes wrong? How long will it take to roll the change back? How many customers will be impacted? Do you have a playbook for this rollback?

This would only try to import missing advisories, so if it goes wrong, it'll
result in the advisory not being imported so nothing will change, and no need
for a rollback.

### What's the worst thing that could happen with this change? How will you deal with it if that thing happens?

I guess if somehow the imported advisory had wrong data, it would lead to
bad/missing security updates for Swift once we enable them? This just reuses the
importer class under the hood, and we've not heard of similar issues, but it
there was a bug here, we should notice it and correct it before we enable
security updates for Swift.

### Did you communicate this change with a planned event?

No

### If this change impacts other services or infrastructure, have you communicated with that team to understand what the impact will be?

N/A

### If you're making an architectural change, have you tested it on a smaller scale? Have you consulted experts in those architecture areas?

N/A

### Who are you pairing with to make sure you don't make a mistake when rolling out this change?

**Deployment partner:** @deivid-rodriguez

## Previous deployment patterns

N/A

<!--
If they exist, please link to existing PCRs, playbooks, documentation, or
issues that describes similar situations to your deployment plan.

* _Previous PCR..._
* _Existing playbook..._
* _Issue where we did something similar but didn't use PCRs yet_
