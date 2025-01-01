# 41. Rank web notifications reasons 

Date: 2023-04-19

## Status

Accepted

## Context

In old system `Newsies` single notification to a recipient be be delivered because of a single reason. This logic is based on user action that triggered a notification (explicit subscribers) or Newsies will just pick first matching subscription reason for a given user and list/thread/comment. 

Example: https://github.com/github/github/blob/c42ea27d018b69e8704fa5e624c1dcc9671efb60/lib/newsies/subscriber_set.rb#L87-L107

Implicitly Newsies defines a reason hierarchy: 
1) explicit recipient reasons (mentions, team mentions, review requested)
2) thread subscriptions reasons
3) thread type subscriptions reasons
4) list subscription reasons

Historically we didn't pay attention to such reasons hierarchy in Notifyd delivery pipeline.

Additionally, Notifyd supports delivering notifications to a single recipient because of multiple reasons at once, for example when a user is mentioned in an `IssueComment` and it's subscribed to the `Issue` thread manually and additionally notification user could be watching a repository containing the `Issue` thread.

It led to unexprected behaviour on Web notifications delivered though Notifyd pipeline (see https://github.com/github/notifyd/issues/2783). 
`Mentions` notifications ended up in `Participating` category instead of `Mentioned` on Web notifications that confused some users.

It worth mentioning that Newsies Web notifications don't support mutiple reasons well as `NotificationEntry` allows only single `reason` to be stored on web notifications side.

## Why it's important?
Reasons are widely used in Web notifications filters. Users rely a lot on reason based filters to identify high signal notifications. If Notifyd will pick random reason then notifications - those filters will be broken.

![image](https://github.com/github/notifyd/assets/5173831/0304a091-dc0c-4b80-882f-c660ee6a3abd)

## Decision

We decided to apply ordering logic for reasons on web notifications side.
- `mention`, `team_mention`, `assign` and `review_requested` are reasons that should take precedence over other participating or subscribing reasons.
- `mention` should take precedence over `team_mention` as it's more specific.
- The rest of `participating` reasons should have precedence over subscribing reasons.

When we have `mention` (or `team_mention`) and `assigned` (or `review_requested`), and in this case the preferred behaviour would be:
- In the assign event, the reason for the assignee should be `assign`, even if the assignee is also mentioned.
- For the rest of notifications, if the assignee is mentioned, `mention` takes precedence over `assign`.

The same approach should be used if we replace `mention` by `team_mention` or `assign` by `review_requested`.

The way web notifications currently work, in order to achieve this behaviour both the `reason` and the `subject_type` need to be taken into account.
See https://github.com/github/notifyd/issues/2783#issuecomment-1525819915 for details.

## Consequences

- If there are several `reasons` for same notification Notifyd will have determenistic logic to pick reason to display for web notification.
- Reasons can stil be overriden for the thread in subsequent web notification.
