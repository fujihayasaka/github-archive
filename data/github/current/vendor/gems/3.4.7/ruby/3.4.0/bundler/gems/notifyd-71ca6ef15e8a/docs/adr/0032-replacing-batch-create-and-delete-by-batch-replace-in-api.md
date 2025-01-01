# 32. Replacing BatchCreateAndDelete by BatchReplace in subscriptions and routing settings API

Date: 2022-08-25

## Status

Accepted

## Context

Initially the subscriptions API had a `BatchCreateAndDelete` method that would be used both for individual subscription replacement and for batch migration.
Later, when working on routing settings API, the same approach was followed.
During CI activity migration, several problems were [found out with this approach][1], particularly for individual routing setting / subscription changes:
- The replace process was suboptimal and required more API calls than needed:
  - A `BatchGet` request to get existing subscriptions / routing settings.
  - A `BatchCreateAndDelete` request with the result of the previous request to replace them.
- A race condition exists as things may have changed between the `BatchGet` and `BatchCreateAndDelete`.

## Decision

A new `BatchReplace` API method will be introduced to replace `BatchCreatAndDelete` in the workflow explained above.
The payload of the `BatchReplace` method will be something like:
```ruby
custom_fields: [{name: "", value: ""}],
to_create: [
  {user_id: 1, name: "", filters: []},
]
```

The operation needs to be transactional per user, but not globally, to reduce the contention.

## Consequences

- The new workflow will be as follows:
  - A `BatchReplace` request includes custom fields to find and delete existing subscriptions / routing settings and the new subscriptions / routing settings to create.
  - This replacement is done within a database transaction.

[1]: https://github.com/github/notifyd/issues/1464
