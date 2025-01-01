# 20. Access mysql2 for mobile device tokens

Date: 2021-09-03

## Status

Accepted

## Context

In [11. Duplicate mobile device tokens into the new service](0011-duplicate-mobile-device-tokens-into-the-new-service.md) we decided to duplicate the tokens from the monolith to `notifyd` via an API request. We successfully shipped this implementation but it has since caused issues. Mismatches have been found between the newsies and notifyd when there is a delay in replication. This dialutes the validity of the dark ship experiment as it's difficult to identify real mismatches vs false positives. Additionally we have found that the API requests have impacted notifyd's availability ([ref 1](https://github.com/github/notifyd/issues/330), [ref 2](https://github.com/github/notifications/issues/1192)).

We explored a few options to solve this problem:

1. Moving the replication from application based replication to replication at the database layer. We discarded this option because we don't want to touch the DB layer in Newsies and `mysql2` which is currently not backed by Vitess (which provides vreplciation as a feature that we could have used for that purpose).
2. Making the API more resilient to spikes in identical requests. We discarded this option because it seemed very challenging to synchronize two databases on the application level in a performant and reliable way. Long term we only want to use a single DB to store the device tokens, so it didn't seem like a good option to invest a lot of effort into a temporary solution.
3. Reading device tokens directly from `mysql2` in notifyd.

## Decision

After some discussion with @mikrobi we believe that the notifyd database should own this data in the long term, but in the short term we will implement option **3.** while notifyd and newsies co-exist. By doing this, it will make the service more reliable as we gain confidence in the logic. Additionally, we believe this will significantly reduce the number of mismatches we are seeing due to replication lag.

**This is a short term tradeoff, we are committed to notifyd owning this data but believe that now is not the right time.** When we are in a position to disable push notifications in newsies, we should tackle this question again and address the problem more holistically.

We explored two different approaches:

- 1. Read directly from `mysql2` from notifyd. We discarded this option because notifyd would rely on a table schema that is owned and managed in the `github/github` repo, so other developers could accidentally break notifyd without knowing by changing the schema in the monolith. We also realized that our setup for the local dev and the test environment would become much more complex if we'd connect to an external database that isn't part of the notifyd repo.
- 2. We use the existing `Api::Internal::Twirp::Notifications::Notifyd::V1::NotifydAPIHandler#check_deliver_mobile_push_policy` twirp API to read the tokens from the monolith

**Decision**

We will implement option **2.** Instead of returning `true` or `false` the API could return an array of device tokens. With this option we can read the data from mysql2 without a big delay, we wouldn't add an additional network request and notifyd wouldn't be coupled to mysql2 directly.

## Risks

- The load is not a risk because we are only reading from the database.
  - **Acceptable risk:** We are pretty good at scaling read load and expect the traffic here to be minimal.
- We are mixing the responsibility of `Api::Internal::Twirp::Notifications::Notifyd::V1::NotifydAPIHandler#check_deliver_mobile_push_policy`
  - **Acceptable risk:** Given this is going to be a semi-temporary solution.
- We rely much more on the robustness of this the monolith-twirp connection
  - **Mitigation:** We will prioritize https://github.com/github/notifyd/issues/126 as part of production readiness.
### Benefits

- Allows us to gain confidence on parity between newsies/notifyd
- Allows us to reduce the reliability concern with storing mobile device tokens in notifyd without significant investment

### Drawbacks

- Temporarily violates [3. Minimise requests from the notifications service back to the monolith](./0003-minimise-requests-from-the-notifications-service-back-to-the-monolith.md)
