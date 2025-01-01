---
name: Initiative
about: Formalized template for tracking new work
title: 'Initiative: $Initiative Title Here'
labels: initiative
assignees: ''

---

## 💬 Overview

A 1-2 paragraph overview of what we are intending to accomplish.

## 💥 Impact

Why are we doing this? Include relevant customers, projected uptake numbers and how we hope to measure the success of this Initiative.

## 🧾 Tasks

Lay out the tasks here as links to Issues; break out appropriate levels for Epics and Batches as needed.

## 🐿 Release Plan

Please fill in a high level overview of how we intend to release this. Include details like what targets we are shipping to (GHES, GHAE, GHEC, etc) as well as potential roll-out plans (Staff Shipping, Private Betas, etc). Please make note of any specific testing that might be involved - such as running things in a custom environment for a week or something similar. Also, please make note if we are targeting a specific Enterprise Release (eg: 3.5) and any associated release dates thereof.

## 🚀 Pre-release Checklist

Generally, for anything that we consider to be an Initiative or higher - you will need to complete the following steps before shipping.

- [ ] New Metrics added to Datadog
  - [ ] Line item metrics go here
  - [ ] Line item metrics go here
- [ ] New Metrics added to Looker / Hydro
  - [ ] Line item metrics go here
  - [ ] Line item metrics go here
- [ ] Go / NoGo Meeting Complete with at least DRI, EM and PM signing off. `yyyy/mm/dd`
- [ ] Docs Complete
- [ ] Product Review Complete
- [ ] This Project will have a full roll-out process
  - [ ] Release Issues logged for roll-outs so that stakeholders are notified
  - [ ] Customers identified for Private Beta
  - [ ] Announcements queued up for Public Beta
  - [ ] `yyyy/mm/dd to yyyy/mm/dd` Staffship 
  - [ ] `yyyy/mm/dd to yyyy/mm/dd` Private Beta 
  - [ ] `yyyy/mm/dd to yyyy/mm/dd` Public Beta
  - [ ] `yyyy/mm/dd` GA 
- [ ] This project will NOT have a full roll-out process and will go straight to production
  - [ ] GA `yyyy/mm/dd`
- [ ] Public Roadmap Card Complete
- [ ] Shipping celebrated!

## ⚠️ Identified Risks

Before and throughout this project, link out to Issues describing any ongoing Risks that this project may encounter. Examples may include things like Recent Dotcom Outages, Slow CI Builds or Global Pandemics.

## ✅ Issue Readiness Checklist

Please do not begin work on this Issue until the following are completed:

- [ ] Overview is filled out
- [ ] Impact is filled out
- [ ] Tasks are created as Issues and we have a rough understanding of what's needed to complete this project
- [ ] Release Plan is Filled Out
- [ ] Shipping section has been reviewed and roughly matches our Release Plan
- [ ] Team assignment has been completed and Engineers are prepped to work through the tasks listed above
- [ ] An estimated completion date is filled out in the sidebar to the right
- [ ] `yyyy/mm/dd` Kick-off Meeting Scheduled
- [ ] `yyyy/mm/dd` Go / Nogo Meeting Scheduled (DO THIS AT THE START)
