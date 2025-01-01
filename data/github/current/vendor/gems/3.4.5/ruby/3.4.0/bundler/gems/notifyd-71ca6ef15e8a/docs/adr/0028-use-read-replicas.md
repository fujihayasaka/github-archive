# 28. Use read replicas

Date: 2022-05-10

## Status

Accepted

## Context

We had a discussion on the [brief for database improvements][1] and [the following proposal on implementation][2] on how to handle read traffic in notifyd.

## Decision

We will use separate connection objects injected into application structs to denote read and write connections.

## Consequences

- within app logic the correct connection object needs to be chosen
- every app struct gets 2 connections handed in via a database struct even if it's not needed
- there is no implicit default connection, all connection types must be explicitly chosen

[1]: https://github.com/github/notifyd/blob/main/docs/briefs/database-improvements.md
[2]: https://github.com/github/notifyd/blob/main/docs/proposals/database-improvements.md
