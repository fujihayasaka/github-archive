# 33. Experimenting with dropping thread auto-subscriptions for Gists

Date: 2022-09-19

## Status

Accepted

## Context

During discussion on the topic of thread auto-subscription migration we involved product to gather their point of view.
As a result, we made a decision for Gist thread auto-subscription migration.

## Decision

- When a notification needs to be delivered for Gist related activity, the following Gist participants need to be notified:
  - Gist author will be included with reason `author`.
  - Gist comment authors will be included with reason `comment`.
  - Individual mentionees will be included with reason `mention`.
    Mentionees should be notified when they are mentioned in the thread but not in subsequent thread activity (they are stateless).
- This is an experiment and this decision should be reversable till the experiment is considered successful.

## Consequences

- Auto-subscriptions for Gists will not be migrated, at least initially.
- Gist participants should be provided on each notification as explicit recipients.
- Once Gists are migrated to notifyd, dual writes to Gist auto-subscriptions in Newsies should be kept
  until a decision is made about the success of the experiment.
  That is, it should be possible to revert this decision at a later point without incurring data loss.
  The option to revert this decision is not included in the current Gist epic plan, which means a decision reversal implies adjusting the epic schedule or creating new one to handle Gist auto-subscription sync and migration.
  Otherwise, dual writes to Newsies can be stopped once the experiment finishes if the decision described in this ADR is considered the right one.
