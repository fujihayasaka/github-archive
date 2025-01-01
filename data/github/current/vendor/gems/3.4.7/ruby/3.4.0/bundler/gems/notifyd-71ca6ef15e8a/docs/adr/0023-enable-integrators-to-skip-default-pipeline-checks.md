# 23. Enable integrators to skip default pipeline checks

Date: 2021-11-04

## Status

Accepted

## Context

While working on supporting new mobile push notification use case (2-factor notifications) we discovered that the current pipeline did not support the needs of this notification type. One of the use cases that we needed to support was providing a way for integrators (in this case the authnd team) to skip some of the checks that we have in the pipeline. For more details on the requirements please see the [Enable integrators to skip default checks in Notifyd notification pipeline](https://github.com/github/notifyd/blob/0cad6d4bd69639344db53a22f0e10190751c29da/docs/briefs/enable-integrators-skip-default-checks.md) brief.

## Decision

We [explored possible solutions](https://github.com/github/notifyd/blob/main/docs/proposals/enable-integrators-skip-default-checks-proposal.md) to this problem and agreed on a [solution](https://github.com/github/notifyd/blob/main/docs/proposals/enable-integrators-skip-default-checks-proposal.md#proposed-solution).

**High level overview**

We will leverage the existing notifyd pipeline to allow integrators to skip certain checks. Integrators should be able to customize the filters either by omitting contextual data in the `Notify` hydro message and/or by adding domain specific logic to the existing hook points in the monolith that notifyd uses to enforce delivery policies.

Below is an example illustration of how this works:

![image](https://user-images.githubusercontent.com/1643158/138927220-355d51f3-7fd3-4d14-817e-636407e450ad.png)

## Benefits 

- It keeps integrator changes scoped to a single file
- Does not require us to expand the scope of the interface of the notify hydro event

## Consequences

- For now we accept integrator specific logic in Twirp API which is a pattern that we want to deprecate at some point in the future
