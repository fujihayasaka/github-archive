# 42. Unsubscribe tokens data

Date: 2023-05-25

## Status

Accepted

## Context

[Currently](https://github.com/github/notifyd/pull/1765) unsubscribe tokens created by Notifyd are very long. They can potentially exceed maximum URL size. The reason for that is we encode a big chunk of event data when creating tokens. This data is passed to email consumer from notify consumer in match_data field: https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/notifyd/v0/deliver_email.proto#L43

This field contains all the event data used to to match subscriptions and routing settings. It has been implemented this way to provide the possibility to unsubscribe from granular events. However, with this approach we cannot control the size of the token because match data that includes topics and attributes of the event are specified by integrator and can potentially be very large. This can be the cause of broken unsubscribe URLs in the future.

That is why we've decided to find a solution that both covers our existing cases and also ensures that token is short in size, size is controlled by Notifyd and does not vary much.

## Decision

As per [discussion](https://github.com/github/notifyd/issues/2098) we arrived at the following solution.
1. Token data shall be versioned to enable us to adjust the content of a token if requirements change in the future.
2. Token will include subject id and subject type of a notification event.

Format of the token data:

```json
[2, "issue", 123]
```
We use array in order to reduce token size. We also put only values in the array without keys to save the space. The data from the token can be extracted following specification: First element is a token version, second element - subject type and third - subject id.



This should be passed in `Data` field in the GetDeliverEmailData Twirp call to Monolith:
https://github.com/github/notifyd/blob/0212c2ec008a262b146ca0674c62b5adff5aff7d/internal/pkg/dotcom/policy/checker.go#L124-137

Source of `st` field is a [`subject_type` field](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/notifyd/v0/deliver_email.proto#L37) of a `DeliverEmail` message.
To get `sid` (`subject_id`) we shall be taking [`Subject.Value` field](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/notifyd/v0/notify.proto#L90) from Notify message and pass it to the deliver-email consumer as `subject_id`.


On the Dotcom's side we shall make sure that we support the old version of Notifyd token. For that, we need to introduce versioning of the token data when parsing unsubscribe link: https://github.com/github/github/blob/master/packages/notifications/app/models/notifyd/unsubscribe_from_link.rb


## Consequences

- tokens won't be exceeding URL's max allowed size and we avoid having broken unsubscribe links