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

# *2023-06-27* *Update ScheduledJobs::EnqueueScheduledUpdates::Daily to run on the hour*

**Primary:** @jurre
**Deployment Partner:** TBD

## Status

<!-- Include one of the following statements: -->

This PCR is available for full review before any steps are taken to modify
production.

<!-- If the change was rolled back or caused in incident, please include the relevant information here -->

## Context

As described in https://github.com/github/dependabot-updates/issues/3635 timerd
backed `ScheduledJobs::EnqueueScheduledUpdates::Daily` jobs currently run at
~56 minutes past the hour.

To do this, we'll need to modify the timestamp that timerd stores to determine
when a given job last ran.

### Risk Assessment

<!-- Please select from one of the following and detail why this level was chosen -->

- [ ] **Low risk** the modifications are small, highly observable, and easily rolled back.
- [x] **Medium risk** changes that are isolated, reduced in scope or could impact few users and not bring the site down.
- [ ] **High risk** changes are those that could impact our customers and SLOs, low or no test coverage, low observability, or slow to rollback.

### Affected services

dependabot-api

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

0. Double check the current time on the instance in UTC:
```ruby
Time.now
=> 2023-06-27 15:57:06.867272463 +0000
```

0. Check that the job just ran:
```ruby
Time.at Dependabot.redis.get("timer:ScheduledJobs::EnqueueScheduledUpdates::Daily").to_i
=> 2023-06-27 15:56:04 +0000
```

0. Grab the integer value in case we need to reset it for whatever reason:
```ruby
Dependabot.redis.get("timer:ScheduledJobs::EnqueueScheduledUpdates::Daily").to_i
=> 1687856164
```

0. Reset the timestamp to the beginning of this hour:
```ruby
Dependabot.redis.set("timer:ScheduledJobs::EnqueueScheduledUpdates::Daily", DateTime.now.beginning_of_hour.to_time.to_i)
```

0. Validate that the new timestamp is what we expect it to be:
```ruby
Time.at Dependabot.redis.get("timer:ScheduledJobs::EnqueueScheduledUpdates::Daily").to_i
=> 2023-06-27 15:00:00 +0000
```

0. Manually run the job so we don't skip an hour
```ruby
ScheduledJobs::EnqueueScheduledUpdates::Daily.perform_later
```


Repeat those steps for the weekly job:

```ruby
Time.at Dependabot.redis.get("timer:ScheduledJobs::EnqueueScheduledUpdates::Weekly").to_i

weekly_old_value = Dependabot.redis.get("timer:ScheduledJobs::EnqueueScheduledUpdates::Weekly").to_i

Dependabot.redis.set("timer:ScheduledJobs::EnqueueScheduledUpdates::Weekly", DateTime.now.beginning_of_hour.to_time.to_i)

Time.at Dependabot.redis.get("timer:ScheduledJobs::EnqueueScheduledUpdates::Weekly").to_i

ScheduledJobs::EnqueueScheduledUpdates::Weekly.perform_later
```

And for the monthly job as well:

```ruby
Time.at Dependabot.redis.get("timer:ScheduledJobs::EnqueueScheduledUpdates::Monthly").to_i

monthly_old_value = Dependabot.redis.get("timer:ScheduledJobs::EnqueueScheduledUpdates::Monthly").to_i

Dependabot.redis.set("timer:ScheduledJobs::EnqueueScheduledUpdates::Monthly", DateTime.now.beginning_of_hour.to_time.to_i)

Time.at Dependabot.redis.get("timer:ScheduledJobs::EnqueueScheduledUpdates::Monthly").to_i

ScheduledJobs::EnqueueScheduledUpdates::Monthly.perform_later
```

## Safe Deployment Checklist

Here are the answers to the [Safe Deployment Checklist](https://thehub.github.com/epd/engineering/dev-practicals/service-lifecycle/safe-deployment-checklist/#safe-deployment-checklist),
including justifications for why some may not apply.

<!--
Many of the answers here should be answered by the previous section.

Refer to numbered steps above as appropriate.
-->

### Have you tested this change before production?

I have tested all the non-destructive steps.

### Where will this change roll out to when it deploys (canary / production / other)?

Production

### Is this change behind a feature flag? (if not, why can't it be feature flagged)?

Not possible, updating timerd to look at flags would be more risky IMO.

### How will you know when this change is rolled out and what it's impact is? Do you have metrics you can watch?

Look at [the Dependabot Background Jobs Dashboard](https://app.datadoghq.com/dashboard/zkv-j25-nxb/dependabot-background-jobs?fullscreen_end_ts=1687878679792&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1687792279792&fullscreen_widget=2256833356651370&from_ts=1687792301487&to_ts=1687878701487&live=true).

Filter it down to `scheduled_jobs/enqueue_scheduled_updates/daily` and verify
that it ran twice fairly shortly after each other. The time that's reported in
datadog lags behind when the job actually runs a little.

We should also keep an eye on [SQS Incoming Jobs](https://app.datadoghq.com/dashboard/4pc-8bd-zmj/dependabot-sqs-jobs?fullscreen_end_ts=1687879386851&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1687792986851&fullscreen_widget=6615137219800566&from_ts=1687792981838&to_ts=1687879381838&live=true)
We expect to see a steady inflow of jobs, where right after we've rolled out the
change we'll see two spikes relatively short after each other.

Jobs starting https://app.datadoghq.com/s/59fe6c40c/fc8-kbh-9vk
Cancelled jobs https://app.datadoghq.com/s/59fe6c40c/jzt-zmj-wuy
Aqueduct https://app.datadoghq.com/dashboard/vmq-gt6-2h7/aqueductdeveloper?from_ts=1687807530081&to_ts=1687811130081&live=true

### Does this change potentially increase load on a database or other dependencies?

No

### Do you have a plan for monitoring any load increase and turning the change off if it reaches a certain threshold?

N/A

### If this change could cause a high severity outage, do you have paging alerts for monitoring thresholds so you can roll it back before that happens?

N/A

### Can you optimize this change to reduce load?

N/A

### How will you roll this change back if something goes wrong? How long will it take to roll the change back? How many customers will be impacted? Do you have a playbook for this rollback?

We can reset the timerd timestamp:

```ruby
Dependabot.redis.set("timer:ScheduledJobs::EnqueueScheduledUpdates::Daily", previous_timestamp)
```


### What's the worst thing that could happen with this change? How will you deal with it if that thing happens?

A larger than expected number of jobs is enqueued in Aqueduct, a lot of jobs run
at the same time and they get cancelled due to GitHub rate limit errors. This is
what's happening now.

### Did you communicate this change with a planned event?

TBD

### If this change impacts other services or infrastructure, have you communicated with that team to understand what the impact will be?

N/A

### If you're making an architectural change, have you tested it on a smaller scale? Have you consulted experts in those architecture areas?

N/A

### Who are you pairing with to make sure you don't make a mistake when rolling out this change?

**Deployment partner:** TBD

## Previous deployment patterns

N/A
<!--
If they exist, please link to existing PCRs, playbooks, documentation, or
issues that describes similar situations to your deployment plan.

* _Previous PCR..._
* _Existing playbook..._
* _Issue where we did something similar but didn't use PCRs yet_
-->
