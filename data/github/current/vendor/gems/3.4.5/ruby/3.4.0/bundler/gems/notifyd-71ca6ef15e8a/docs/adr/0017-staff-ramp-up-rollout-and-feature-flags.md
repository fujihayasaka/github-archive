# 17. Staff ramp up rollout and feature flags

Date: 2021-06-29

## Status

Accepted

## Context

While staff shipping push notifications with notifyd for `Issue` and
`IssueComment` we needed a way to easily and safely add new staff members to
the experiment.

## Decision

We decided to add a guard into the scientist checks for feature flags that made
sure:

 - Only staff users receive push notifications through notifyd
 - Only dotcom deployments send push notifications through notifyd

The relevant change can be found [here](https://github.com/github/github/pull/182178/files#diff-66334eb68a3342b22bc1667da48c6e6cfba6e7a18c82ec3e86ec39740563f9a9R10-R11)

## Consequences

### Benefits

We can now ramp up with the darkshipping utility on devtools only for the GH
staff.

### Cons

Before Beta or GA we need to reevaluate this. Probably activate these
feature-flags for the staff group while ramping up for beta/GA.
