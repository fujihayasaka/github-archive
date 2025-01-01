---
name: "\U0001F333 Root cause analysis template"
about: Create an issue to perform an RCA of an alert.
title: Root cause analysis template
labels: RCA
assignees: ''

---

👋 A way of training the oncall muscle is to, every time an alert fires, perform a root cause analysis.
Use this template to ease the information gathering process and to understand the definition of done for the analysis.

### Start date and time

Date/time in UTC when we started to fail our SLO

### End date and time

Date/time in UTC when we fully recovered

### Impact

* Users affected
* During how long
* What was the impact in users: unable to create runner, VM creation stopped, data loss...

### How did we respond to the issue 

Self recovered/paused and resumed queues/delivered a fix...

### What was the root cause of the incident?

Brief description of the root cause of the incident

## Did we change our status from green?

Yes/No

### Was this due to a bad deploy?

Yes/No

### Detailed analysis

- Course of events that lead to the incident (no need for a detailed timeline here, high level overview suffices)
- It's recommended to link to datadog graphs and any relevant screenshots to the issue to ease readability 

### Open questions and action items
- Links to issues to tackle action items to improve our reaction to the issue next time or to prevent it from ever
 happening again
- Open questions we still do not have answers for

### Have we updated relevant playbooks?

* [ ] playbook 1
* [ ] playbook 2


cc:
@github/compute-flex