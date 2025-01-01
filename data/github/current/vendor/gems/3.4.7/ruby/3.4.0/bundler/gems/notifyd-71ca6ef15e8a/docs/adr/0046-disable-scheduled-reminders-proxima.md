# 46. Remove scheduled-reminders from Proxima

Date: 2023-10-02

## Status

Accepted

## Context

North star: Scheduled reminders with Slack and Teams integrations are available in all GitHub environments including GHES and Proxima. 

But there are a few facts:
- We do not have capacity to solve multi-tenancy and other Proxima onboarding ‘must-have’ items in Q2, F24. 
- Keeping scheduled-reminders enabled on Proxima is going to cause escalation and bugs for the team.
Obviously, we can keep explaining that eventually we are going to work on that, but it is an additional burden for the team. It doesn't help customers nor does it help the team. 
- [GHES release] gets higher priority because 1) we already have a huge amount of customers onboarded to this environment 2) we have direct customer escalation to enable scheduled-reminders
3) effort is estimated as low

## Decision
Q2, F24 decision: Focus on launch of scheduled-reminders for GHES and disabling it on Proxima stamps.

[GHES release]: https://github.com/github/notifications/issues/2153
