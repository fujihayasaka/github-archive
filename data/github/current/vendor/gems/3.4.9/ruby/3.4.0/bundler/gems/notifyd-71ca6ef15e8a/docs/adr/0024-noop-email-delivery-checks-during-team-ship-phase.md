# 24. Noop email delivery checks during team ship phase

Date: 2021-12-03

## Status

Accepted

## Context

While developing the [email channel prototype][1] we wanted to keep a parallelism with the checks the push notification delivery currently implements with a `monolith-twirp` RPC call.

In addition to that we wanted this RPC call to return the email address that `notifyd` had to use in order to deliver the email.

The goal of this prototype was to outline the E2E process that would allow us to deliver an email for an event triggered from the monolith, so the specifics of the checks itself are not important right now.

## Decision

In the process of developing this RPC endpoint we decided that:

- The check would be `noop` for now and would only do a feature flag check as an initial approach. Such feature flag can be removed later on.
- We would perform email routing by using what is already built into newsies, without adding any new support for it into `notifyd`. In particular `Organization#user_can_receive_email_notifications?(user)` and `Organization#notifiable_emails_for(user)`. See [here][4]
- We would hardcode `notifyd` to always use the `github` organization ID when performing the checks so that all test emails arrive always to our `@github.com` addresses, no matter the subject of the notification.

## Consequences

Once we move forward with the email channel and iterate on it, we will need to dedicate some time to review these trade offs and make sure that:

- We have a proper email routing if it is needed.
- The hardcoded organization ID is removed and changed by the received organization ID as explained [here][2]
- The feature flag is removed as explained [here][3]

[1]: https://github.com/github/planning-tracking/issues/585 "Email channel prototype"
[2]: https://github.com/github/notifyd/issues/563 "Remove the hardcoded GH org ID on the delivery check"
[3]: https://github.com/github/notifyd/issues/565 "Remove the testing feature flags"
[4]: https://github.com/github/github/blob/40249324798d8fdb6508cebf26d96a5b8a95cdfe/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L26-L28 "Email routing"