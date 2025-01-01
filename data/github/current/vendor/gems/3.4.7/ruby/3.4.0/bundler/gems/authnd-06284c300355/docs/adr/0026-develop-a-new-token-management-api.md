# 26. Develop a new token management API (Project Mint)

Date: 2021-06-11

## Status

Accepted

## Context

Authnd currently supports authenticating a (large but incomplete) subset of GitHub authentication tokens via replication.
This means token issuance and revocation are still coupled to the monolith, and increases the impact replication lag can have on the usage of tokens (since tokens must also replicate over to authnd).
This replication model was intended as a first step towards authnd _owning_ credential data and management.

Tokens are a critical piece of the GitHub authentication story.
They are now the only way to authenticate to the GitHub API, and are strongly recommended (along with SSH Public Keys) for authenticating Git access.
However, the current token implementations have some limitations:

* All token types are issued by the monolith.
  * This hinders our ability to isolate other components (Git operations, certain APIs, etc.) from the monolith.
  * Services like GitHub Insights, Container Registry, etc. have had to use Monolith APIs to perform authentication.
* Implementations of token types are spread throughout the monolith and while there is quite a bit of consistency, achieving that requires manual maintenance.
* Token data is stored in the main `mysql1` cluster
  * This increases the impact of a potential security compromise in our database infrastructure.
  * Horizontally scaling (aka sharding) `mysql1` data is a costly task
* There is no centralized revocation system for tokens. This increases the complexity of secret scanning tools by requiring that they can identify a token type.
* Token validation is frequently subject to replication lag issues
  * Validating with authnd requires waiting for the token to replicate from mysql1 through Maxwell.
  * Even validation directly within the monolith [requires complex replica selection logic](https://github.com/github/github/blob/25d279a4ff4e4c4b85cb7b129a3e094b3a83c9e2/lib/github/authentication/token_lookup.rb#L29).
  * Customers [have reported this impact in the past](https://github.com/github/ecosystem-apps/issues/1059)

There are also new proposals like [Personal Access Tokens v2 (PATv2)](https://github.com/github/public-interfaces/issues/64) and [Service Tokens](https://github.com/github/ecosystem-apps/issues/1063) that place additional demands on our token infrastructure.
We also anticipate enterprise requirements, such as supporting Identity Provider (IdP) issued tokens, which will further increase the complexity of token authentication in both dotcom and GHAE.

## Decision

The authentication team will add token management APIs to authnd for use in dotcom and eventually GHES/GHAE (though the latter is not in scope yet).
These APIs will provide functionality for issuing, authenticating, modifying, revoking and querying tokens.
Consuming services can use these APIs and apply their own business logic to provide user-facing token experiences.

### Goals

* **Provide a central point of storage and validation for tokens**, allowing for future security enhancements.
* **Define a single consistent token format** that can be easily detected and revoked by our security scanning products
* **Provide a central point of revocation** for new token types and a way for dependent teams to be notified when their tokens are revoked.
* **Provide a highly-available and reliable token management service** that can operate independent of github/github
* **Standardize metadata associated with tokens** while also allowing extensibility so that new token types can encode the appropriate context (user identity, application identity, scopes, etc.)

### Non-Goals

* We **do not** want to interfere with how consuming teams build user experiences. Our goal is to centralize token management but allow consuming teams flexibility to define the functionality associated with tokens.
* We **do not** intend to create front-end UI or APIs to manage tokens at this time.

### Token Format

The authnd service will define the physical token format.
Consuming services should not store the issued tokens and should treat them as opaque strings to be transmitted to/from clients.
Retaining control over the token format allows authnd flexibility to adapt the format as necessary to support further growth (such as, for example, storing data directly within the token to improve scalability).
Authnd's tokens will be uniquely distinguishable from existing tokens, to allow services to identify when a token **must** be processed by authnd.

### Token Attributes

In authnd, authenticating any credentials (including tokens) results in a set of *attributes*.
Attributes encode data about the authentication context such as the user identity, the identity of the OAuth/GitHub App they are authenticating through, any credential authorizations ("SSO blessing") and scopes that may limit access granted by the token.
A token is, in effect, a trusted pointer to a collection of attributes which will later be used to authorize user actions.

Tokens issued by authnd will be required to adhere to a strict attribute "schema" defining the names and types of attributes, but this schema will be updatable and can be adapted to whatever data consuming services need to associate with tokens.

More information can be found in [5. Attribute model](https://github.com/github/authnd/blob/main/docs/adr/0005-attribute-model.md) and [14. Attribute schema](https://github.com/github/authnd/blob/main/docs/adr/0014-attribute-schema.md).

### Provided APIs

We will provide APIs via new Twirp method calls and APIs (exact format TBD) in the existing authnd service.
As part of this work, we'll investigate a richer service-to-service auth format that allows us to concretely identify the calling service, so that we can store that data alongside tokens.

#### Issue token

We will provide a new `IssueToken` API to issue a new token, given a set of attributes.
The caller will provide the attributes to be encoded by the token, and authnd will respond with the token value itself, as well as an ID value.

In addition to attributes, an expiration time can be provided (Open Question: Or maybe *must* be provided?), after which the token will fail to authenticate.
We could provide notification of token expiration, though that isn't currently in scope in this proposal.

Along with other token metadata, the service which requested the token be issued would be tracked.

#### Authenticate token

A token can be authenticated using the existing `Authenticate` API, which will be updated to support these new tokens.
The caller provides the token value and receives back the current set of attributes associated with the token.
Included as part of those attributes would be the unique token ID generated by authnd when the token was issued.

#### Query tokens

Open Question: We need to know how much flexibility is needed here as it will affect how we store tokens.

A new `QueryTokens` API will allow looking up what tokens have already been issued for a particular combination of attributes.
The intent here is to allow consuming services to provide user-facing services to _manage_ their existing tokens.
For example, this API would allow a consuming service to retrieve all "Personal Access Tokens" issued to a user, or all tokens issued to a user by a given Application, etc.
In response to a query, the calling service would get the ID values of the tokens that match the query (but **not** the token value itself) as well as the attributes associated with each token.

Providing a query API will require careful design as it can negatively impact the scalability of the system.
Supporting complex and arbitrary queries may limit our ability to shard the data.
It is critical that we get a clear understanding of the querying requirements our partner teams have.
This includes both the query types needed **and** latency expectations for those queries.

#### Modify tokens

Using the token ID (as returned by either the `IssueToken` or `QueryTokens` APIs), a `ModifyToken` API would allow changing certain attributes of the token.
This would allow for changing cosmetic attributes such as a "Title" displayed in a UI, as well as more functional attributes like Credential Authorizations.

Not all attributes of a token would be mutable.
Part of the work of designing the attribute schema with partner teams would be identifying which attributes can be mutated and which must be immutable for the life of the token.

#### Revoke tokens

Using **either** the token ID or the actual token value, the `RevokeToken` API would cause the token to immediately (subject to replication lag) become unusable.
In addition to identifying the token to be revoked, other metadata such as a reason for the revocation could be provided.

## Consequences

Centralizing token management allows us to make changes to token handling and storage without requiring changes across the monolith.
Moving the complete token lifecycle out of the monolith also allows more services to isolate themselves from the monolith's failure domain.

A service dedicated to credential management will be easier to scale independently of the monolith, and provides better opportunities for both vertical scaling (having sufficient capacity in our hardware to handle the traffic) and horizontal scaling (sharding and other data model changes to better distribute load).
Implementing this service will require significant design work on the data model to ensure it can scale to the level we need.

Requiring monolith-based services to make an API call to resolve tokens will likely have an impact on latency.
However, this impact is generally low, particularly on the p50 (current authnd p50 latency is ~4ms).

Given the existing impact of replication lag, we will need to develop a design that can prioritize consistency when issuing tokens, to ensure that when a token is given back to a user, it is immediately usable.
Our premise is that replication lag is **more acceptable** when revoking or modifying an existing token and **less acceptable** when issuing a token (consider OAuth scenarios where a token is often issued and then immediately used by the requesting application).
