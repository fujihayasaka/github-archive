# Authnd Chatops

## Overview

We have added chatops to

- ping the service
- get the hmac
- run the profiler

PR: https://github.com/github/hubot-classic/pull/3635, https://github.com/github/authnd/pull/57

## Commands

- `.authnd hmac`
- `.authnd ping`
- `.authnd pprof --profile {profile_name}` where profile_name is one of the [profile names](https://golang.org/pkg/runtime/pprof/#Profile)

## Other helpful commands

- `.catalog docs authnd` will list our playbook, dashboards, and monitors.
