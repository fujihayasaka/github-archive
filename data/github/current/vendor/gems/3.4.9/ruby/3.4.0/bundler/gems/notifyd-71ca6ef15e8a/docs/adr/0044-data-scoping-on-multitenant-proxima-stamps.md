# 44. Data scoping on multitenant Proxima stamps

Date: 2023-07-05

## Status

Accepted

Continuation of [Multi-Tenancy management](/docs/adr/0043-multi-tenancy.md)

## Context

In the context of preparing `notifyd` for [multitenancy], after making sure we
passed all necessary headers to downstream services, we were left with the
question of whether we needed the `tenant_id` to be present on our database
queries to uniquely identify each user across tenants and stamps.

## Decision

After a review of the existing documenation for [Proxima] and consulting with
the relevant teams we've decided that we will skip propagating the `tenant_id`
down to our database queries.

The reasoning behind this decision is:

- User IDs are unique on a single stamp (even across tenants)
- `notifyd` uses a different database **per stamp**
- Our code identifies users only by their `id` and never with other systems
  like `login`.

Given that, we can be sure that on a given stamp, a `user_id` uniquely
identifies the user without needing to also use the `tenant_id`.

## Consequences

- The necessary work to propagate the `tenant_id` to the DB queries can be
  avoided.
- The existing `tenancy` package that provides the necessary data structures to
  propagate the headers on requests to downstream services might be simplified.
- A conversation about whether validating the input and ensuring authorization
  in base of the _current user_ is responsibility of `notifyd` or its caller
  has been deferred and can be tracked on this [issue]

[multitenancy]: https://github.com/github/proxima/blob/main/docs/tenancy/multi-tenancy.md "Multi Tenancy"
[proxima]: https://github.com/github/proxima "Proxima"
[issue]: https://github.com/github/notifyd/issues/3077
