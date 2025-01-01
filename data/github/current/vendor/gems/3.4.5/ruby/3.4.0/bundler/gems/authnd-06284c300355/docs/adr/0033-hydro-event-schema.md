# 33. Authnd credential event hydro schema

Date: 2021-12-01

## Status

Accepted

## Context

PATv2 tokens provide a more flexible and extensible token management system that gives more granularity to users and organizations. Authnd owns the management of these tokens, but there are other parties that need to be aware of PATv2 token events that occur in Authnd. The goal of this document is to describe the hydro schema that Authnd will use to publish event messages that can be consumed by other services. This would be scoped to PATv2 tokens but we should keep in mind that this decision may impact other credential types as Authnd assumes more responsibility.

This topic will enable Ecosystem Apps to cleanup Apps-owned DB records when the associated tokens are expired or revoked through another flow (i.e. secret scanning).
Ecosystem Apps will also want to consume this information from the monolith to send mailers and notify users when PATv2 tokens are issued, revoked and expiring, and the schema defined here may be added-to and consumed by the monolith to instrument audit logs.

## Decision

- Event notifications will be published to a single hydro topic that consumers will filter by event type.
- Authnd will publish messages on token issuance & revocation as well as on token expiration, and 1 and 7 days before token expiry.
- The hydro topic will be defined by the credential type, but not split into multiple topics for each event (`cp1-iad.ingest.authnd.credential.(ProgrammaticAccess.staging/production).v0.Event`).

### Hydro schema attributes

- `actor_id` (`int64`)
- `credential_id` (`int64`)
- `credential_suffix` (`string`) - equivalent to `token_suffix`
- `credential_expires_at_utc` (`google.protobuf.Timestamp`) - timestamp when the credential expires
- `credential_issued_at_utc` (`google.protobuf.Timestamp`) - timestamp when the credential was issued
- `access_id` (`int64`) - the credential's oauth access identifier
- `catalog_service` (`string`) - the service that triggered this event
- `request_id`  (`int64`) - the request ID associated with this event (null except for issue and revoke)
- `event_type` (`enum`) - the reason for the event:
  - `issued`
  - `revoked`
  - `expired`
  - `expiration_warning`
- `event_reason` (`string`) - nullable & mostly informational
  - `exposed_credential` -  when the revoke event was triggered by secret scanning
  - `7d`, `1d` - tracks the time until expiration when the `event_type` is `expiration_warning`
- `send_notification` (`bool`) - indicates if users should be notified of the event (false if event was triggered by secret scanning)

## Consequences

We're currently only publishing events for PATv2 tokens. We'll need to decide hydro needs for different event notification scenarios as they occur in the future, but this decision starts the pattern of one topic being defined per credential type rather than having a single topic for all events (which would be inefficient for consumers with a single credential focus) while also not splitting the topic by `event_type` (which would allow for more fine grained filtering).
This is fine for our current needs because the planned monolith PATv2 consumer will need to react to all event messages that we plan to publish. In the future we we may need to create multiple topics for a single credential, or add an additional topics for a different credential type because of the hydro topic granularity that we chose here.
