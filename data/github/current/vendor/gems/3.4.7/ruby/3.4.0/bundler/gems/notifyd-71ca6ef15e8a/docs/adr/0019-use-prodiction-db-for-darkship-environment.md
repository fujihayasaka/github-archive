# 19. Use production DB for darkship experiment

Date: 2021-08-04

## Status

Accepted

## Context

We need to enable darkship experiment for broader userbase to track notification mismatches between `newsies` and `notifyd`.
But as we have already implemented checking mobile device tokens in `notifyd` and are very close for implementing tracking deliveries on `notifyd` side, darkship experiment needed access to production data, to have minimal number of mismatches.

This is needed because nothing is writing or synching tokens into the `darkship` environment and the tokens are needed to "simulate" deliveries. In other words, we only attempt deliveries when a token exists for a user and if we don't have the same tokens as in production we won't attempt the same deliveries.

Specifically we thought about tracking deliveries between `production` and `darkship` environments.
In this usecase we need to store delivery data in database. If `production` and `darkship` data was out of sync - it could potentially lead to false positive mismatches.
We want `darkship` experiment to use real/production data for the experiment to ensure that delivery would have worked the same way as it did for production environment.

Team has considered multiple options:

1. Plainly writing from `darkship` environment on the production mobile deliveries table.

   We initially discarded this option because it would mean that both `production` and `darkship` would write and read deliveries. Meaning that the first env to write a delivery would "deliver" while the second one would treat the message as a duplicate.

   We would no longer be able to publish the same hydro message to both environments in parallel and would have to change `gh/gh` code to exclusively publish the message to a single environment. It wouldn't be possible to run the darkship experiment and deliver pushes via notifyd for the same user at the same time.

2. Maintaining copy of production database for darkship environment and running replace device tokens transition against darkship envronment.

   Was discarded because it also means we would need to resynchronise every token on prod/darkship so each call to the twirp API would need to happen once per env or be duplicated somehow.

3. Setting up darkship environment to access production database and storing tracked deliveries into separate table on production db.

   Was discarded because it would imply that migrations have to run on both tables and introduces an extra bit of complexity in that case because of things like data transitions.

4. Setting up darkship environment to access production database and adding column to indicate environment for tracked delivery.

   We initially chose this option as the solution we wanted to implement. The immediate cost was clear (add a column and use it in the code). Long time cost was partially known (we would need to clear darkship deliveries eventually), there might be other costs related to volume of data but none came to our mind that was an immediate problem. We wouldn't care about the combination of feature flags.

5. Get rid of the `darkship` environment and run our experiment in a different way.

   In particular we talked about adding a new `dryRun` flag to the `notify` message. This flag would mean that `notifyd` would only log the push notification delivery rather than sending it. This would have the same effect as the darkship environment without the extra operation al cost.

   We discarded this option because it has many other immediate costs that we're not ready to asume.

## Decision

 - Our initial decision was to implement option `4.`
 - After a thorough debate we decided to implement `1.` instead.
 - The reason to change our mind was based on a mistaken assumption. We had initially considered that the data produced by the experiment on the `mobile_notification_deliveries` table was "garbage". This wasn't true.

## Benefits/Reasoning

 - The data written by the `darkship` environment is a type of prefilling that will be useful when moving `notifyd` to GA. We'll need a transition to store deliveries from newsies to this new system and having this data will help us reduce the cost of that transition.
 - It has the smaller operational cost now and the future cost is, for now, apparently non-existent.
 - We treat the `darkship` environment as a sort of `review-lab` which is a known pattern.
 - We reduce the impact of the `darkship` on `notifyd` but as [the observer effect](https://en.wikipedia.org/wiki/Observer_effect_(physics)) states we're aware that we can't measure a system without modifying it. For now we accept the changes this imply.

### Drawbacks

 - We had initially implemented option `4.` and we had code ready to get it to production and we had to undo it.
 - We need a new PR that makes the `notify` and `darkship` feature flags mutually excluyent on `gh/gh`.
