# sweagentd First Responder

[First responder training recording - 2025-05-16](https://microsoft-my.sharepoint.com/:v:/p/chrimartin/EXUcfHEzRwdFnSmce0T_tTwBtS_gCvhWJSHN_HdYtKggfQ?e=hwjJss&nav=eyJyZWZlcnJhbEluZm8iOnsicmVmZXJyYWxBcHAiOiJTdHJlYW1XZWJBcHAiLCJyZWZlcnJhbFZpZXciOiJTaGFyZURpYWxvZy1MaW5rIiwicmVmZXJyYWxBcHBQbGF0Zm9ybSI6IldlYiIsInJlZmVycmFsTW9kZSI6InZpZXcifX0%3D) 

## 1. Rotation

A shift is Wednesday morning through Wednesday morning, including off hours pages, organized through the [coding-agent-ep escalation policy](https://github.pagerduty.com/escalation_policies/P29A2BN).

## 2. Responsibilities
While you are the team's First Responder, you will take care of the following items in descending priority order:

1. **Respond to pages and active incidents:**
   - Your first mission is to make sure sweagentd is healthy, and when we have incidents staying engaged (even when it's a dependency issue) is priority number 1. Details on how to do this can be found in [our playbook](https://github.com/github/ops/blob/master/docs/playbooks/copilot/coding-agent.md).
1. **Monitor service health:**
   Check these out every so often throughout the day to make sure things look good.
   - [sweagentd's dashboard](https://app.datadoghq.com/dashboard/4wj-b2t-r9p/sweagentd) looks healthy
   - (We need to clean up Sentry a bit before we can expect FR to actively monitor this:) [sweagentd's sentry](https://github.sentry.io/issues/?project=4508892525559808&query=is%3Aunresolved%20issue.priority%3A%5Bhigh%2C%20medium%5D&referrer=issue-list&statsPeriod=24h) does not show any new or escalating issues
   - **This now includes Proxima!**
      - Our [sweagentd dashboard](https://app.datadoghq.com/dashboard/4wj-b2t-r9p/sweagentd) supports different environments, check out our production proxima environments!
      - Subscribe to [#sweagentd-proxima-alerts](https://github-grid.enterprise.slack.com/archives/C09AWA9CSTF)
      - Investigate any reported outages and get familiar with the [proxima specific monitors](https://app.datadoghq.com/monitors/manage?q=sweagentd%2Fproxima).
      - Take a look at [how-can-i-debug-proxima](https://github.com/github/sweagentd/blob/main/docs/proxima-docs.md#how-can-i-debug-proxima)
      - If usage is rising and it looks like we can tighten monitors up, at least make sure to **create a first-responder issue**!
1. **Work on and Triage the First Responder Tasks**
   - Go through support escalation issues on [this board](https://github.com/orgs/github/projects/21230/views/48) and triage any support tickets that have not been replied to.
       - There is upcoming automation to make this process easier and less involved https://github.com/github/sweagentd/issues/7460, but until then first responders are expected to evaluate the support issues (in collaboration with product team).
   - Go through issues on [this board](https://github.com/orgs/github/projects/21230/views/43) if there are no active incidents or urgent issues that you are working on.
   - Improve our processes! Create an issue on the board to track gaps in our [playbooks](https://github.com/github/ops/tree/master/docs/playbooks/copilot/coding-agent/tsg) and/or monitoring.
   - Triage issues on the board. Work with your manager and the team to decide which issue(s) are worth prioritizing.
   - Move all of the open security vulnerability [issues](https://github.com/github/vuln-mgmt/issues/) to our board and prioritize/resolve. You can search for coding-agent to find issues that pertain to us.
   - Did you get paged this shift? If so, write up an issue for a resolution so we don't get paged for the same issue again!
1. **Engage users seeing operational issues with the product:**
   Make sure to take some time of the day to check in on common areas folks may need help.
   - #coding-agent
   - #coding-agent-team
   - #coding-agent-dogfood
   - [Microsoft's Teams dogfood channel](https://teams.microsoft.com/l/channel/19%3Ae54177e89c2a463db213a00c2bf33e95%40thread.tacv2/Padawan%20internal%20dogfood%20feedback?groupId=4c7d9ea8-db48-4929-889b-ba32c90d5274&tenantId=72f988bf-86f1-41af-91ab-2d7cd011db47)

At the beginning of your shift, make a point to:
  - Update the #coding-agent-dogfood and #coding-agent-team channels to include the current first responder and drop the old one.
  - Get any one-off coverage in PagerDuty that you may need for, e.g doctor appointments, etc.

At the end of your shift, make a point to:
  - Add an entry to the [handoff discussion](https://github.com/github/sweagentd/discussions/2450) detailing your week.
  - Attend the on call handoff discussion or touch base with the person coming on call next async.

## 3. Fallback

If you're unable to follow up on all these items at any point in your rotation, please work with the team to hand items off directly. It is not your responsibility to complete all the tasks, such as provide continuous reviews on all PRs, but to triage and delegate to experts where needed.

## 4. Useful Places and Things

Slack channels:

* [#coding-agent](https://github-grid.enterprise.slack.com/archives/C08BT2TUJNA)
* [#padawan-dogfood](https://github-grid.enterprise.slack.com/archives/C08DGM5ULJ3)
* [#coding-agent-team](https://github-grid.enterprise.slack.com/archives/C0891ESUXGW)
