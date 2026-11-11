# ADR: Server-to-Server Token Minting via Twirp

## Status

Proposed

## Date

2025-01-21

## Deciders

@arthurnn @tarebyte @cschleiden @colbylwilliams @Chuxel

## Related Issue

[#9488 - Decouple token minting from App private keys via Twirp endpoint](https://github.com/github/sweagentd/issues/9488)

## Context

### Current State

Today, sweagentd holds GitHub App private keys for each agentic app (Copilot, Claude, Codex). Whenever the service needs to make a server-to-server (s2s) API call, it uses the private key to mint a token locally, then makes the API call.

This approach has several drawbacks:

1. **Key management burden** - Private keys must be injected as environment variables and rotated across all service deployments
2. **Security surface** - Private keys exist in the service's memory/environment, increasing blast radius if the service is compromised
3. **Coupling** - Adding new agentic apps requires injecting additional private keys into the service
4. **Ownership constraint** - Holding private keys requires GitHub to own all agentic apps (we need stable access to the keys). This blocks the ability to support third-party owned apps/engines where partners own and manage their own GitHub Apps.

### Requirements

- sweagentd must not hold GitHub App private keys
- Token minting must work for all agentic apps (Copilot, Claude, Codex, future partners)
- Existing caching behavior in sweagentd must continue to work
- Authentication to the new endpoint must use existing Twirp client infrastructure

## Alternatives Considered

### 1. Continue holding private keys (status quo)

Keep the current approach where sweagentd holds private keys and mints tokens locally.

**Rejected because:**
- Does not scale as we add more agentic apps (each requires new key injection)
- Higher security risk with keys in service memory

### 2. Twirp endpoint on dotcom (selected)

Add a new RPC method to the existing `SweagentdAPI` service that mints s2s tokens, mirroring the existing `MintUserToServerTokenForRepo` pattern.

**Selected because:**
- Reuses existing Twirp client infrastructure and authentication
- No new service dependencies
- No need for sweagentd to have access to private keys
- Scales naturally as new agentic apps are added (just need app ID)

## Decision

Add a new `MintServerToServerTokenForRepo` RPC method to the `SweagentdAPI` Twirp service in the monolith. sweagentd will call this endpoint to obtain s2s tokens instead of minting them locally with private keys.

### API Design

```protobuf
// In sweagentd_api.proto

// MintServerToServerTokenForRepo mints a server-to-server token for the given agent and repository.
rpc MintServerToServerTokenForRepo(MintServerToServerTokenForRepoRequest) returns (MintServerToServerTokenForRepoResponse);

message MintServerToServerTokenForRepoRequest {
  // The agent id (GitHub App ID) for the agent that we want to get a token for.
  int64 agent_id = 1;
  // The github repository id for the repository to scope the token to.
  uint64 repository_id = 2;
}

message MintServerToServerTokenForRepoResponse {
  string token = 1;
  // Unix timestamp indicating when the token expires
  int64 expires_at = 2;
}
```

### Implementation Approach

1. **Monolith (github/github):**
   - Add `MintServerToServerTokenForRepo` handler to the existing `SweagentdAPI` Twirp handler
   - Handler finds the agent in the agent registry by `agent_id` and uses the existing mechanisms to mint a repository-scoped server-to-server token
   - Returns the token to the caller

2. **sweagentd:**
   - Add client method to call `MintServerToServerTokenForRepo`
   - Refactor the mint token methods in the existing agentic app implementations (Copilot, Codex, Claude) to use this Twirp API instead of the public REST API
   - Remove private key environment variables once migration is complete
   - Existing caching layer continues to work unchanged (caches the returned tokens)

### Sequence Diagram

```
┌──────────┐                    ┌──────────┐                    ┌─────────────┐
│ sweagentd│                    │  dotcom  │                    │ GitHub Apps │
└────┬─────┘                    └────┬─────┘                    └──────┬──────┘
     │                               │                                 │
     │ MintServerToServerTokenForRepo│                                 │
     │ (agent_id, repository_id)     │                                 │
     │──────────────────────────────>│                                 │
     │                               │                                 │
     │                               │ Mint token                      │
     │                               │────────────────────────────────>│
     │                               │                                 │
     │                               │<────────────────────────────────│
     │                               │ token                           │
     │<──────────────────────────────│                                 │
     │ token                         │                                 │
     │                               │                                 │
     │ Use token for API calls       │                                 │
     │                               │                                 │
```

## Implications

### What becomes easier

- **Adding new agentic apps** - No need to inject new private keys into sweagentd; just use the app ID
- **Key rotation** - Keys only exist in the monolith; rotation doesn't require sweagentd redeployment
- **Security posture** - Reduced attack surface; sweagentd never holds private keys
- **Proxima deployments** - No need to create new private key environment variables, configure vaults, and inject them into Proxima environments; token minting works automatically by calling the dotcom API

### Migration Plan

1. Implement the new Twirp endpoint in dotcom
2. Add client method in sweagentd behind a feature flag
3. Gradually roll out, validating token minting works correctly
4. Once validated, remove private key environment variables from sweagentd configuration
5. Remove legacy private key minting code from sweagentd

## Additional Details

### Caching

There are two layers of caching for s2s tokens:

1. **sweagentd caching** - The service already has caching infrastructure for tokens. The new endpoint returns a token with its expiration, and sweagentd caches it as it does today. Cache TTL and invalidation behavior remain unchanged.

2. **Monolith caching** - The new Twirp handler in the monolith must implement the same caching strategy that currently exists in the REST endpoint for minting s2s tokens. This ensures we don't unnecessarily mint new tokens on every request.

### Authentication

The new RPC method uses the same Twirp client and authentication mechanism as existing methods (e.g., `MintUserToServerTokenForRepo`, `ConfigurationForRepository`). No changes to authentication are required.
