# 21. Tracking end to end metrics

Date: 2021-09-27

## Status

Accepted

## Context

While preparing for [critical QoS][1] the need to track some metrics end 2 end on the delivery process arose.

In general things like:

 - `triggered_at` or a similar timestamp representing the time when the event happened that eventually resulted in a request to `notifyd`.
 - `request_id` or other type of request correlation mechanism
 - `user_agent`/`integration_name` or a similar way to identify an integration and track their metrics so that, eventually, they can monitor their own metrics.
 - Others like `repository_id`, `subject_id`... for similar reasons.

And, in particular for our [current epic][1] a timestamp like `queued_at` is a blocking concern for our progress.

Possible options are:

- Add the single field needed in order to unblock the epic at the event level
- Add a new `tracking` entity to the events and start filling it up in following iterations with the needed information
- Use the timestamp present on the hydro messages envelop (discarded since that wouldn't be an end to end as it wouldn't include the time spent on job processing on the monolith)

## Decision

We decided to add a new `tracking` entity to the `notify` and `deliver-mobile-push` messages so that we could the necessary metrics end to end and to conveniently decouple the tracking data from the business related.

The reason for doing this now rather than later is because we've identified at least 2 more pieces of information that we would want in order to help ourselves debug and support notifyd:

- `request_id`
- `user_agent`

And having them grouped gives us a convenient wrapper for propagation and isolation.

## Consequences

We will need to conveniently change the [hydro schema][2] to reflect this change and then update our [publisher][3] in the monolith and [the one on notifyd][4] to properly fill in this information.

This will open the gate for our code on `notifyd` to make the necessary calculations that help us track end 2 end metrics on the service.

We don't have other clients yet (for example for Go codebases) but the Authorization team has expressed their will to use notifyd from their service [Authnd][5] and we'll most likely need to help with making these changes there if they reach notifyd's production once they are finished with their integration.

Last, but not least, by adding more fields to the `notify` message we are slightly increasing the complexity of the interface to `notifyd`. This is not a problem yet but complexity is an attribute that tends to accumulate in a way that goes unnoticed so better to be conscious about it given that this is an integrator facing part.

[1]: https://github.com/github/planning-tracking/issues/498
[2]: https://github.com/github/hydro-schemas/tree/main/proto/hydro/schemas/notifyd/v0
[3]: https://github.com/github/github/blob/7e7e0d56e8113846709b7cee1f2b08fd348a8ff0/app/models/notifyd/notify_publisher.rb#L77-L94
[4]: https://github.com/github/notifyd/blob/b7a457dfd876d88274f5bbc504024dc979100df0/internal/notify/consumer.go#L114
[5]: https://github.com/github/authnd
