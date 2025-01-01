# 18. Make requests to the monolith for notification specific auth checks

Date: 2021-07-28

## Status

Accepted

Amends [3. Minimise requests from the notifications service back to the monolith](0003-minimise-requests-from-the-notifications-service-back-to-the-monolith.md)

## Context

Similar to [15. Make requests to the monolith for mobile push checks during the migration to notifyd](0015-make-requests-to-the-monolith-for-mobile-push-checks-during-the-migration-to-notifyd.md) we have a number of auth based delivery checks that must be implemented in notifyd for it to reach feature parity with newsies:

1. Mobile push notifications should be skipped if the user is suspended
2. Mobile push notifications should be skipped if the user is of a type Bot/Org

Each of these features requires functionality to be implemented in notifyd _and_ authzd. The problem is that we don't currently have a good pattern for testing the connections between the monolith triggering notifications for a spammy user, notifyd checking authzd, and notifyd producing the right result. This increases the risk of any rollout and will make it harder to rollout notifyd and build confidence.

## Decision

To make the rollout more incremental, it is proposed that first we leave these checks in the monolith and make twirp requests from notifyd back to the monolith to perform these checks.

After we have this in place we can migrate each of the checks to use authzd once we land on a good testing pattern.

## Consequences


- This should be a shorter and faster path to getting the delivery logic in notifyd to match what we have in newsies today.
- This will let us increase the number of notifications we are sending via notifyd sooner.
- Once in place we can migrate each check individually to notifyd in a lower risk way.
- This also allows us potentially to run both the new notifyd checks and the monolith checks, and compare results.
- Allows us to evaluate our testing strategy holistically

### Drawbacks

- The monolith twirp api knowing about auth checks is a leaked abstraction
- We are continuing to rely on the monolith for auth checks which is ill-advised for [these](https://github.com/github/authzd/blob/master/docs/how-authzd-works.md#why-do-we-need-authzd) reasons
