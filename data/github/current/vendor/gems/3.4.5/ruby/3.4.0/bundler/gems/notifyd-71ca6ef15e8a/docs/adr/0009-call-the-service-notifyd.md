# 9. Call the service notifyd

Date: 2021-03-26

## Status

Accepted

## Context

We need a catchy name for the new service.

The old notifications system (inside the monolith) is called "newsies".

"Notifications" is too generic and hard to grep for accurately (we already get pinged when `ActiveSupport::Notifications` appears in stack traces, even though it's a core component of Ruby on Rails.

Our initial versions were named "notifications-go" but this has all the flaws of "notifications" and has an unnecessary reference to a specific programming language.

## Decision

We will call the service `notifyd`.

## Consequences

### Benefits

- `notifyd` is short
- `notifyd` is catchy
- `notifyd` is unique and easy to grep for
- `notifyd` describes what the service does
- `notifyd` is pronouncable (either as "notified" or "notify-dee")
- `notifyd` sits nicely next to other services (`authnd`, `authzd`, `babeld`)
