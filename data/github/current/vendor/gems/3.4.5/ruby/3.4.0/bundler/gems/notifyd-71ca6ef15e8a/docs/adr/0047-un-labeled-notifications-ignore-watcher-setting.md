# 47. (Un)Labeled notifications ignore email watcher settings

Date: 2024-04-19

## Status

Accepted

## Context

_Label subscriptions_ is an experimental feature that is currently only supported for issues in notifyd open only to GitHub and a small number of organizations (LLVM, Python and Rust).
They behave as a special kind of repository subscriptions and when used the user will:
- Receive notifications related to issues with labels they are subscribed to.
- Receive notifications when issues are added / removed the labels they are subscribed to.

This second type of notifications should only be received by users subscribed to the labels, not all the watchers. In order to do that, it cannot be considered _watcher activity_ and this means that Watching settings are not respected properly.
A [Settings for Label Subscriptions] discussion was created to discuss possible outcomes but no further action was taken. After receiving another [bug report] the topic was discussed again and a decision was taken.

## Decision

The current behaviour won't be fixed in the short term and this will be considered as a known issue until a proper solution is implemented.

## Consequences

- This issue will be added to the list of [known issues].
- This issue will be eventually addressed with a long term solution.


[Settings for Label Subscriptions]: https://github.com/github/notifyd/discussions/3362
[bug report]: https://github.com/github/notifications/issues/2923
[known issues]: ../KNOWN_ISSUES.md
