# sweagentd First Responder

[First responder training recording - 2025-05-16](https://microsoft-my.sharepoint.com/:v:/p/chrimartin/EXUcfHEzRwdFnSmce0T_tTwBtS_gCvhWJSHN_HdYtKggfQ?e=hwjJss&nav=eyJyZWZlcnJhbEluZm8iOnsicmVmZXJyYWxBcHAiOiJTdHJlYW1XZWJBcHAiLCJyZWZlcnJhbFZpZXciOiJTaGFyZURpYWxvZy1MaW5rIiwicmVmZXJyYWxBcHBQbGF0Zm9ybSI6IldlYiIsInJlZmVycmFsTW9kZSI6InZpZXcifX0%3D) 

## 1. Rotation

A shift is Wednesday morning through Wednesday morning, including off hours pages, organized through the [coding-agent-ep escalation policy](https://github.pagerduty.com/escalation_policies/P29A2BN).

**Important:** No feature work when on the FR rotation. Focus should solely be on service health. We need to account for that in planning and make sure first responders have the time.

## 2. Responsibilities
While you are the team's First Responder, you will take care of the following items in descending priority order:

1. **Incidents/Pages:**
   These take priority over everything else.
   - Help out with incidents that affect CCA.
   - Declare CCA incidents if needed.
   - Your first mission is to make sure sweagentd is healthy, and when we have incidents staying engaged (even when it's a dependency issue) is priority number 1. Details on how to do this can be found in [our playbook](https://github.com/github/ops/blob/master/docs/playbooks/copilot/coding-agent.md).

1. **Alerts:**
   Investigate any alerts that happen in the [#sweagentd-alerts](https://github-grid.enterprise.slack.com/archives/C08PS7VEL3B) channel. Many should also page, but the First Responder must also keep an eye on non-paging alerts that fire. Our goal has to be that every alert we see is actionable and is from an underlying issue.
   - Determine the cause of the alert (e.g., bad deploy, changed customer behavior, noise).
   - Take appropriate action: tweak the alert if it is noise, or create an (investigate) incident.

1. **Customer Support Escalations:**
   Triage incoming support escalations and follow up on already created ones.
   - Go through support escalation issues on [this board](https://github.com/orgs/github/projects/21230/views/48) and triage any support tickets that have not been replied to.
   - Determine if the issue can be answered right away.
   - Identify issues that require bigger fixes and should be linked to something on the backlog.
   - Route issues to another team if necessary.

1. **SLOs:**
   Keep an eye on our SLOs.
   - Check if any SLOs are red and determine the root cause.
   - Monitor SLO trends, error budget, and burn rate.
   - Investigate and fill out any pings from slo-bot ([example](https://github.com/github/sweagentd/discussions/9177))

1. **Monitor Slack Channels:**
   Make sure to take some time of the day to check in on common areas folks may need help.
   - [#coding-agent](https://github-grid.enterprise.slack.com/archives/C08BT2TUJNA)
   - [#coding-agent-team](https://github-grid.enterprise.slack.com/archives/C0891ESUXGW)
   - [#copilot-coding-agent-feedback](https://github-grid.enterprise.slack.com/archives/C08DGM5ULJ3)
   - [Microsoft's Teams dogfood channel](https://teams.microsoft.com/l/channel/19%3Ae54177e89c2a463db213a00c2bf33e95%40thread.tacv2/Padawan%20internal%20dogfood%20feedback?groupId=4c7d9ea8-db48-4929-889b-ba32c90d5274&tenantId=72f988bf-86f1-41af-91ab-2d7cd011db47)
   - Respond to questions or forward them to the right people to answer.

1. **Security Vulnerabilities and Dependabot:**
   - [Dependabot Updates](https://github.com/github/sweagentd/pulls/app%2Fdependabot)
   - [Open Vulnerabilities](https://github.com/github/vuln-mgmt/issues?q=is%3Aissue%20state%3Aopen%20label%3A%22Owner%3A%20coding-agent-core-team%22)

1. **Improve Livesite Health and Tooling:**
   Proactively look for issues in our telemetry.
   - Analyze for any developing trends.
   - Investigate buckets of job failures to identify underlying issues.
   - Go through [First Responder Issues](https://github.com/orgs/github/projects/21230/views/43) if there are no active incidents or urgent issues that you are working on.
   - Improve our processes! Create an issue on the board to track gaps in our [playbooks](https://github.com/github/ops/tree/master/docs/playbooks/copilot/coding-agent/tsg) and/or monitoring.
   - Triage issues on the board. Work with your manager and the team to decide which issue(s) are worth prioritizing.
   - Fix [sentry issues](https://github.sentry.io/issues/?project=4508892525559808) and [improve performance](https://app.datadoghq.com/apm/traces?query=env%3Aproduction%20service%3Asweagentd&agg_m=count&agg_m_source=base&agg_t=count&cols=core_service%2Ccore_resource_name%2Clog_duration%2Clog_http.method%2Clog_http.status_code&historicalData=false&messageDisplay=inline&query_translation_version=v0&sort=desc&spanType=all&storage=hot&view=spans&start=1768502954296&end=1768503854296&paused=false)
   - Did you get paged this shift? If so, write up an issue for a resolution so we don't get paged for the same issue again!

1. **Monitor Service Health (including Proxima):**
   Check these out every so often throughout the day to make sure things look good.
   - [sweagentd's dashboard](https://app.datadoghq.com/dashboard/4wj-b2t-r9p/sweagentd) looks healthy
   - (We need to clean up Sentry a bit before we can expect FR to actively monitor this:) [sweagentd's sentry](https://github.sentry.io/issues/?project=4508892525559808&query=is%3Aunresolved%20issue.priority%3A%5Bhigh%2C%20medium%5D&referrer=issue-list&statsPeriod=24h) does not show any new or escalating issues
   - **This now includes Proxima!**
      - Our [sweagentd dashboard](https://app.datadoghq.com/dashboard/4wj-b2t-r9p/sweagentd) supports different environments, check out our production proxima environments!
      - Subscribe to [#sweagentd-proxima-alerts](https://github-grid.enterprise.slack.com/archives/C09AWA9CSTF)
      - Investigate any reported outages and get familiar with the [proxima specific monitors](https://app.datadoghq.com/monitors/manage?q=sweagentd%2Fproxima).
      - Take a look at [how-can-i-debug-proxima](https://github.com/github/sweagentd/blob/main/docs/proxima-docs.md#how-can-i-debug-proxima)
      - If usage is rising and it looks like we can tighten monitors up, at least make sure to **create a first-responder issue**!

At the beginning of your shift, make a point to:
   - Update the #coding-agent-dogfood and #coding-agent-team channels to include the current first responder and drop the old one.
   - Get any one-off coverage in PagerDuty that you may need for, e.g., doctor appointments, etc.

At the end of your shift, make a point to:
   - Add an entry to the [handoff discussion](https://github.com/github/sweagentd/discussions/2450) detailing your week.
   - Attend the on call handoff discussion or touch base with the person coming on call next async.

## 3. Fallback

If you're unable to follow up on all these items at any point in your rotation, please work with the team to hand items off directly. It is not your responsibility to complete all the tasks, such as provide continuous reviews on all PRs, but to triage and delegate to experts where needed.

## 4. Resources

### Azure Data Explorer:
   - Failed jobs: [Dashboard Link](https://dataexplorer.azure.com/dashboards/efdfd276-7d76-4177-89bb-a6e2d2b83407)
      - Includes drill downs view for specific job failures, very helpful to look at job failures in public repositories.

### DataDog:
   - Reliability: [Dashboard Link](https://app.datadoghq.com/dashboard/asx-99z-w6j)
   - APM: [APM Link](https://app.datadoghq.com/apm/entity/service%3Asweagentd?dependencyMap.showNetworkMetrics=false&env=production&graphType=flamegraph&groupMapByOperation=null&historicalData=true&operationName=sweagentd.consumer&shouldShowLegend=true&spanKind=consumer&traceQuery=&start=1767888148987&end=1767902548987&paused=false)
   - Overall monitoring: [Dashboard Link](https://app.datadoghq.com/dashboard/4wj-b2t-r9p/sweagentd)
   - Job Completion SLO: [Dashboard Link](https://app.datadoghq.com/notebook/13776229/cca-job-completion-slo)

### Sentry:
   - sweagentd: [Issues Link](https://github.sentry.io/issues/?environment=production&environment=staff-wus2-01&project=4508892525559808&statsPeriod=1h)
   - CCA runtime specific view: [CCA View Link](https://github.sentry.io/issues/views/195902/?environment=production&project=4508892525559808&query=is%3Aescalating%20error.type%3A%2Aagentcallback.Agent%2AError&sort=date&statsPeriod=7d)

### Slack Channels
These channels may provide further signal on active issues:
   - [#copilot-coding-agent-feedback](https://github-grid.enterprise.slack.com/archives/C08DGM5ULJ3)
   - [Microsoft's Teams dogfood channel](https://teams.microsoft.com/l/channel/19%3Ae54177e89c2a463db213a00c2bf33e95%40thread.tacv2/Padawan%20internal%20dogfood%20feedback?groupId=4c7d9ea8-db48-4929-889b-ba32c90d5274&tenantId=72f988bf-86f1-41af-91ab-2d7cd011db47)
