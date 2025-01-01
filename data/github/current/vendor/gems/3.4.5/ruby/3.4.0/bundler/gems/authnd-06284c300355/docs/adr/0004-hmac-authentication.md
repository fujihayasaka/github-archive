# 4. HMAC Authentication

Date: 2020-09-29

## Status

Accepted

## Context

Authnd needs to authenticate callers to its services to protect against unauthorized access.
Being "inside the datacenter" is not a sufficient security protection.

## Decision

We will use the HMAC authentication model defined in `go-twirp`: https://github.com/github/go-twirp/blob/master/server/hooks/auth/hmac.go

Authnd and it's callers will share a secret symmetric key. A caller is expected to generate an HMAC over a timestamp, using that shared key
and include it in the `Request-HMAC` header. Authnd will validate the HMAC and that the timestamp is valid.

## Consequences

The HMAC authentication model is well-known at GitHub and easy to use from the Monolith due to existing libraries.

The use of a shared secret symmetric key is very limiting. All apps that want to access Authnd must copy the secret key in to their Vault.
This also makes rolling the key very complicated.

However, we don't want to reinvent an existing pattern. There are groups working to improve service-to-service communication at GitHub
and this ADR can be superceded when a new system exists.
