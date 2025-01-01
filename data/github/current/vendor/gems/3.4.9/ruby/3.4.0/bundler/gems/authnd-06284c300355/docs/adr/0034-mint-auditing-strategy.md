# 34. PATv2 Auditing Strategy

Date: 2021-12-03

## Status

Accepted

## Context

As part of [Project Mint](https://github.com/github/authnd/issues/1011), we introduced support for issuing tokens from Authnd to support the PATv2 initiative.   As a new token issuance service, we need to ensure all notable operations on those tokens are audited and available for owning identities (i.e. users, orgs, and businesses).  Additionally, a durable audit trail is invaluable for incident response, forensic auditing, support tickets, etc.

## Decision

All auditing for PATv2 operations will be instrumented through Apps-supported code in the monolith.  That comes in two forms:
1. Instrumentation in the ProgrammaticAccess AR model's actions ([example for updates](https://github.com/github/github/blob/78faaf93e9a23683759068b1cfc2056f1a4d0289/packages/programmatic_access/app/models/user_programmatic_access.rb#L83-L89)).
2. Instrumentation in a new hydro event processor which will read authnd-generated messages triggered by token issuance/revocation/deletion. Here are the corresponding tracking issues from [Apps](https://github.com/github/ecosystem-apps/issues/1742) and [Authentication](https://github.com/github/authnd/issues/1020). These hydro messages are primarily intended for enabling user notification flows, but can support auditing scenarios as we'll describe below.

All existing credentials issued or owned by dotcom provide audit events for token creation/update/deletion operations, leveraging the [established audit logging](https://thehub.github.com/engineering/products-and-services/internal/audit-log/) path provided through the monolith via [driftwood](https://github.com/github/driftwood). We should maintain the same level of auditing for PATv2.

Here's a breakdown of the operations at question and how they will be audited:

### Token issuance

Currently, PATv2 tokens can only be issued through the web interface whose backend is owned and already instrumented by Apps (as previously mentioned).  Token issuance will be audited as a `user_programmatic_access.create` event ([Appendix](#user_programmatic_accesscreate)).  Also note that PATv2 regeneration is a special case of token issuance from the Authnd perspective, as discussed [below](#other-events).

Additionally, Authnd will be issuing hydro messages whenever tokens are issued via the Authnd API.  Initially these messages will be discarded by the aforementioned dotcom processor.  However, we could use them to trigger audit log messages should we introduce API or service-driven flows for issuing tokens (e.g. through the `gh cli`).

### Token revocation

PATv2 tokens, like PATv1, can be revoked both through the dotcom web interface and through secret scanning.  In the earlier case, the AR model owned by Apps already has the necessary instrumentation which is auditing `user_programmatic_access.destroy` events ([Appendix](#user_programmatic_accessdestroy)).

For secret scanning driven revocation, the Apps code will be bypassed as Authnd is called directly.  As before, an event will generated, sent via Hydro, and ingested by the dotcom processor--at which point, a corresponding `user_programmatic_access.destroy` audit event would be recorded.

### Token expiration

In the event that the authnd-issued token expires, the hydro notification flow will propagate an event to Apps dotcom processor.  At that point, a `user_programmatic_access.destroy` event will be recorded with the expired `explanation`.  This is similar behavior to oauth access token behavior we have today ([Appendix](#oauth_accessdestroy-on-expiration)).

### Other events

At the time of this ADR was drafted, there are two other audit events being issued for PATv2s in dotcom:

The `user_programmatic_access.update` event is generated when an existing PATv2 has its fine-grained permissions modified ([Appendix](#user_programmatic_accessupdate)).  This operation acts on resources in the Apps ecosystem and does not modify the underlying token.  As a result, no auditing is necessary from the Authnd perspective.

The `user_programmatic_access.regenerate` event is generated when an existing PATv2 is regenerated through the dotcom web interface ([Appendix](#user_programmatic_accessregenerate)); this is useful for key rotation or when a user has misplaced their token.  Regenerating the PATv2 issues a new token from Authnd with the same `access_id` and updates the Apps-owned access resources to point to the new token.  From the Authnd perspective, this is indistinguishable from issuing a new token and would result in an "issue token" message in the Hydro notification flow which would be ignored by the upstream dotcom processor.

## Alternatives Considered

As Authnd is the issuer and manager of the tokens, it might make sense for Authnd to originate the audit log events.  This can done by writing directly to the [audit log topic in Hydro](https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=cp1-iad.ingest.audit_log.v2.AuditEntry) or using a bespoke [stream processor in dotcom](https://github.com/github/github/pull/164728).  It's likely that we'll need to originate our own auditing events in this way at some point in the future (i.e. for Mobile 2FA).  However, the Apps code already exists to instrument these audit events for dotcom web traffic and plugging into that logic in the new dotcom processor should be simple.  Moreover, there's a lot of context available in the dotcom web flow which would not be available to Authnd (e.g. user IP, user location, session ID, device cookie, programmatic access information, etc.); that is useful information to include in the audit log.

We also considered auditing authentication requests.  Obviously, there are orders of magnitude more requests authenticating a PAT than creating/modifying/deleting it.  We could throttle how often we'd send audit events for authentication (say hourly?), but that would still generate a tremendous amount of load.  In the end, this feels like a misuse of the auditing system.  Instead, we should decorate our application logs to include the token suffix for authentication requests (at least for PATv2) so authentication requests can be inspected in Splunk for forensic auditing purposes.  This strategy is widely used in the monolith as well.

## Consequences

No new pipeline will be established at this time for sending events directly from Authnd to the audit log.  It seems likely that we'll need to support that in the future, so we are, in effect, delegating future work with this decision.

Any new workflows for issuing/revoking tokens will need to be monitored closely to ensure we do not miss auditing events on tokens through those flows.  As we have to explicitly onboard new services to Authnd for HMAC auth, this risk is minimal.

## Appendix

### `user_programmatic_access.create`
![create PATv2 audit event](https://user-images.githubusercontent.com/7198966/144622307-8a7ea145-e113-47f1-9599-8ba7b466f4bc.png)

### `user_programmatic_access.destroy`
![destroy PATv2 audit event](https://user-images.githubusercontent.com/7198966/144622223-6a5a8d35-42bd-4478-81d2-4232ecc71ae4.png)

### `user_programmatic_access.regenerate`
![regenerate PATv2 audit event](https://user-images.githubusercontent.com/7198966/144676368-3c950a6e-2b77-42b5-b39a-f46b37b8ed76.png)

### `user_programmatic_access.update`
![update PATv2 audit event](https://user-images.githubusercontent.com/7198966/144623221-8a029373-37ca-4990-b39f-02f64eee474e.png)

### `oauth_access.destroy` on expiration
This the existing audit event on token expiration in PATv1
![Screen Shot 2021-12-03 at 4 01 22 PM](https://user-images.githubusercontent.com/7198966/144678497-44c8d35b-fe4e-4afe-8f04-9ec026b1d0d4.png)
