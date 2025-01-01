## CHANGES

This document keeps track of the changes made to the `acme-widgets` metadata.

#### `issue_events`
- Replace `https` with `http` as this is the only file where the two protocols are mixed up. As far as we know, we shouldn't see this in production, if we do, we'll need to add suport for it.

- Replace PR reference in `issue_events_0000002.json` from 3 to 5, to make sure we have at least one batch where all the dependencies exist.

#### `pull_requests`
- Add a `close_issue_references` to a pull request that is not from a fork.

#### `projects`
- Changed monalisa user from http://github.localhost:58231 to http://github.dev to match the other references.

#### `repositories`
- `allow_forking` is set to false because the organization does not allow forking.
- `creator` updated to reflect a more realistic creator URL.
