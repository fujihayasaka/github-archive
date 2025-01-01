# 35. Stateless Tokens and Token Exchange

Date: 2022-04-08

## Status

Proposed

## Context

Traditionally, authentication credentials used at GitHub have been _stateful_; that is, there is some entropy associated with the credential which is stored in a database maintained in GitHub datacenters and validation of that credential includes verifying it against that stored entropy.  There are a few examples (i.e. Signed Auth Tokens) which are hybrid tokens that rely on minimal state on the server-side, however they are exceptions.

By contrast, _stateless_ tokens are credentials which have no state associated on the server-side.  The tokens encode all relevant authentication information about the actor inside the body of the token itself.  Attestation of the token's validity is usually provided through signing of its contents.

These two credential classes are largely _dual_ to each other: an advantage of a stateful token is generally a disadvantage of a stateless tokens (and vice versa).  Here are the characteristics of each across key authentication concerns:

1. **Issuance** -  Because they maintain no state on the server-side, issuing a stateless token requires no writes to a database; their primary cost is the CPU time required to sign/encrypt the token contents.  Contrarily, issuing a stateful token requires at least one write to a database.  The scale/throughput of primary writes is often a limiting factor in the MySQL clusters used at GitHub. Primary writes have lead to continual efforts to horizontally partition pieces of our data model in different clusters (see the [recent conversation](https://github.com/github/data-partitioning/issues/740) around the `authentication_tokens` table in `mysql1`).

2. **Validation** - Validating (or authenticating) a stateful token requires a database read in order to check the corresponding state/entropy.  For stateless tokens which are signed or encrypted, the signing/encryption key (either symmetric or asymmetric) can be used to validate the token without the need for a call to the database.  In particular, that means validation of a stateless token can be done by the application at point-of-use without having to call a central authentication service (i.e. `authnd`).

3. **Revocation** - Revoking a stateful token is as simple as invalidating/deleting the state in the database.  Stateless tokens, however, are difficult to revoke without the usage of a centralized token blocklist which is often impractical.

4. **Expiration** - Stateful tokens often have their expiration maintained along with the state in the database and, as a result, it is enforced by the authentication service during validation.  By contrast, stateless tokens usually encode the expiration time in the token contents and the enforcement of that expiration needs to be handled by the application; this means extra care must be taken when using stateless tokens to ensure the encoded expiration is respected (ideally by a client-side authentication library).

5. **Security** - Both stateful and stateless tokens are susceptible to compromise/leaking to outside sources.  However, stateless tokens are much more vulnerable to forgery.  Weak or compromised signing/encryption keys enable malicious actors to issue valid tokens with arbitrary contents (i.e. for any actor) as long as the compromised key is valid, which is a significant risk.  By contrast, arbitrary forgery (i.e. not just a single actor) for stateful tokens would require a severe security vulnerability at a platform level (e.g. RCE, network takeover, etc.).

The choice of stateless or stateful tokens for a given use case is clearly dependent on the requirements and properties of the system in question.  Largely, stateful tokens have worked very well at GitHub and help us maintain a strong security posture.

However, there are a few concerns we raise with respect to the usage of stateful tokens in the current service architecture today:

1. **Duplicate authentication** - Request authorization requires authentication as a prerequisite. However, there are additional system/application primitives which require authentication attributes as inputs (e.g. feature flagging, rate limiting, etc.). Outside of dotcom, that means an RPC to `authnd` or Dotcom to authenticate the credential at each point-of-use.  As more pieces of GitHub business logic are extracted out of Dotcom and into Moda apps, the potential for duplication of effort (and increased COGS at the platform level) is amplified.  Eliminating that duplication of authentication effort without cheap, client-side validation of credentials is problematic. The simplest approach, which is already used at GitHub, is for downstream services in an RPC chain to trust the authorization decision performed by the initial service in the chain; this poses a clear security risk.  Consider services A and B where service B trusts the upstream verification performed by service A -- if, during the normal course of feature development, service B broadens the  platform options it performs on the user's behalf, any additional permission checks must be reflected in the authorization checks present in service A first.  Drift between the two services present a potential vector for privilege escalation.

2. **Mutable attributes for Authorization** - The desired paved path for Moda services is to use `authnd` and `authzd` for authentication and authorization, respectively.  Currently, this means an `authnd` RPC to validate the provided credential followed by an `authzd` RPC where a subset of the resultant authentication attributes are required as inputs.  Exactly which subset of authentication attributes are required for a given authorization request is sometimes subtle and relies on correct implementation from the calling service.  As the Authentication and Authorization teams don't regularly review code in calling services, this poses a security risk.  We have already seen this happen during the development of the [`goproxy` project](https://github.com/github/identity/issues/577). The Authorization team is already tracking [potential work](https://github.com/github/authorization/issues/2670) to natively support credentials in `authzd` RPCs and perform authentication on the server-side which would largely solve this problem.  However, the duplicate authentication problem described above would still be present.

3. **Plaintext network traversal** - In the current GitHub network architecture, requests over the internal network are not encrypted by default.  This means that any credential provided in a RPC between services in the GitHub datacenter is transmitted in plaintext.  Today, this means user-provided credentials (e.g. PATs) are vulnerable to exposure by malicious actors should they gain access to the GitHub private network (e.g. through MITM, packet sniffing, etc.).  The majority of the credentials that we provide today have a long (if any!) expiration, further exacerbating this problem.  We hope this problem will largely be solved by the [Service-to-Service Authentication Initiative](https://github.com/github/service-to-service/), but we should not rely on this as a given when considering improvements to our security posture.

In order to mitigate these concerns, we propose to introduce a new set of stateless tokens to stand in for user-facing credentials for RPCs inside the GitHub service architecture.

## Decision

We will add support to `authnd` for issuing asymmetrically-signed stateless tokens.  Those tokens will be issuable by a new `ExchangeToken` RPC API which, when presented with a valid authentication credential, will return a new signed token with authentication attributes equivalent to the attributes of the provided credential. Similarly, we will add logic to the `authnd` Go and Ruby clients to validate those stateless tokens using the public key for the associated signing key. For the purpose of authentication with `authnd` (and eventually authorization with `authzd`), these tokens will be functionally equivalent to the tokens from which they were exchanged.

The key attributes of these new stateless tokens are:

1. **Asymmetrically signed** - We need these tokens to be signed to provide attestation that the token is valid and the encoded claims have not been tampered with (i.e that it was issued by `authnd` and is, therefore, trustable).  Importantly, encryption _does not_ provide attestation for a token and, therefore, cannot be used _in lieu_ of signing.  By using an an asymmetric key pair, we can provide the public key to all `authnd` clients to allow verification of the token signature while preserving the exclusivity of the private key to ensure `authnd` is the only server which can issue these tokens. We plan to use an ECDSA NIST-P256 public/private keypair for the signing and verification of these tokens. This cryptographic choice is examined in much greater detail [below](#choice-of-cryptography).

2. **Equivalent claims** - The claims in the stateless token would contain the same attributes which would result from an `Authenticate` RPC call. Ideally, we would provide a uniform API surface for `authnd` clients for retrieving known claims/attributes from the `ExchangeToken` and `Authenticate` RPCs to avoid addition work for upstream developers. Additionally, the claims will contain two additional attributes -- the type and ID of the exchanged credential -- to ensure any actions undertaken using the stateless token are traceable back to the original credential.

3. **Internal** - These tokens are designed for usage by internal systems and are NOT intended to be user-facing.  These tokens will contain a plaintext encoding of authentication attributes; none of these attributes are sensitive (e.g. user ID, oauth access ID, etc.) but presenting them externally would represent a degraded user experience in our view.  Moreover, these tokens will be large and impractical to display in the Web UI (and even CLI).

4. **Short lived** - These tokens would have a short expiration, ideally only on the order of a minute. As these tokens are intended to be used for the lifetime of single user request to GitHub, these tokens need only be valid for the lifetime of the request.  Limiting their validity in this way mitigates security risk in the event of inadvertent compromise of a token.

The tokens serve as an incremental step in the larger Transparent Authentication Initiative where we seek to perform authentication of user-provided credentials exactly once, at the network "frontdoor".  These stateless tokens would then replace the credentials provided by the user in the `Authorization` header so that internal services never see the original credential and require no additional RPCs for authentication.

Notably, we do not make a determination on the specific token format or encoding scheme in this ADR.  We're considering a range of potential token formats including popular open standards (e.g. JWT, PASETO) and bespoke formats (e.g. versioned Protobuf/MessagePack-serialized attributes).  However, we're defering that decision to a later ADR.

### Example (using JWTs)

For the purposes of the example, let us presume that we choose JWT as the method for encoding our token attributes.  As aforementioned, **that decision is not being made here**, but this will give us an idea how that attribute equivalency might look for a given token format.

Consider the following sample PATv2 token with some custom attributes:

```
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
```

Calling the `Authenticate` RPC in `authnd` with this token yields the following attributes:

```
credential.expires_at_utc = [Time] 2022-04-08 17:51:04 +0000 UTC
credential.type = [string] ProgrammaticAccessToken
actor.id = [int64] 1337
actor.type = [string] User
access.id = [int64] 31337
org.id = [int64] 8675309
org.slug = [string] jennycorp
credential.id = [int64] 5
```

The equivalent JWT token exchanged with a proof of concept implementation using EDCSA P256 signing is:

```
eyJhbGciOiJFUzI1NiJ9.eyJhY3Rvci5pZCI6MTMzNywiYWN0b3IudHlwZSI6IlVzZXIiLCJhdHRyIjp7ImFjY2Vzcy5pZCI6MzEzMzcsIm9yZy5pZCI6ODY3NTMwOSwib3JnLnNsdWciOiJqZW5ueWNvcnAifSwiYXVkIjpbImdpdGh1Yi9pbnNpZ2h0cyIsImdpdGh1Yi9hdXRoemQiXSwiZXhwIjoxNjQ5NDQwMjY0LCJpYXQiOjE2NDk3NzE2NDAsImlzcyI6ImF1dGhuZCIsImp0aSI6IjQ4ZmQ0OWE5LTVjYWEtNDIwOC04YzVlLTVhYWEwYzllOTcyZCIsIm5iZiI6MTY0OTc3MTY0MCwib2NpIjoiNSIsIm9jdCI6InByb2dyYW1tYXRpY19hY2Nlc3NfdG9rZW4ifQ.fWsjOU1FFC2VWNbEuWn-1vCzNoBXXxAtDAGFjri7q2N9HS36UsHGaFJNI0N64yUUfwHlIFTkUNGlk7pmxHq1wg
```

The encoded token claims and header information (decoded using [jwt.io](https://jwt.io/)) are as follows:

![Screen Shot 2022-04-12 at 8 54 32 AM](https://user-images.githubusercontent.com/7198966/162978617-b0439921-47b4-4c75-9e61-799e793a0ccc.png)

### Key rotation

We will need to distribute the public keys for any signing keys used by `authnd` to services which need to validate these tokens.  To achieve this, we will provide a `GetVerificationKeys` RPC which will return a protobuf-serialized list of key objects (e.g. [JWKs](https://datatracker.ietf.org/doc/html/rfc7517#section-4) in the case of JWTs) representing all signing keys currently in use by `authnd`.  The `authnd` client will proactively fetch the active keys from this API; a token will be successfully validated if the signature can be verified by any key in the current key set.  

There are a few ways which we can mitigate downtime and system load spikes during key rotation:

1. The key set will be cached in the `authnd` client with a max TTL (say 10 minutes). When the new key is added to `authnd`, we'll continue signing stateless tokens with the old key for at least that max client TTL.  That will allow the clients to gracefully load the new key from the `GetVerificationKeys` RPC before `authnd` begins using it. Additionally, we can emit a server-side stat to gain confidence on the status of the client-side key rotation before activating the new.

2. When activating the new key or removing the old key, any clients which fail a token verification due to key mismatch may try to refresh their key set cache. This will be heavily rate limited to avoid undue load on `authnd`.  However, this is a fallback and should be largely mitigated by the previous step.

### Choice of Cryptography

We examined a number of different cryptographic signing algorithms, as well as one encryption algorithm for reference, to compare their performance and understand their implications.  Here are metrics gathered for each surveyed algorithm for token signing and verification using a [bespoke Go tool](https://github.com/github/authnd/blob/chriskirkland/token-exchange-spike/cmd/jwt-perf/main.go) and `openssl speed`[^1][^2]:

| Algorithm | Type | Go issue/s| Go validate/s| openssl signs/s | openssl verify/s |
| --------- | ---- | -------- | ------------- | ----- | ----- |
| HMAC 256 | symmetric signing | 32108.013 | 47713.863 | | |
| RSA 2048 | asymmetric signing | 728.699 | 13826.851 | 1863.1 | 61535.7 |
| ECDSA NIST-P256 | asymmetric signing | 16363.849 | 10307.881 | 39929.4 | 16192.5 |
| Ed25519 | asymmetric signing | 18496.767 | 13009.350 | 24820.9 | 9176.3 |
| AES-256-GCM | symmetric encryption | 25158.358 | 32188.843 | | |

[^1]: All experiments performed on Mac w/ 2.4 GHz 8-Core Intel Core i9.  `openssl speed` workloads are isolated to single core by default; we used OpenSSL v3.0.2.  Go experiments were restricted to a single core for consistency (e.g. `GOMAXPROCS=1`). More details on these experiments can be found in [this gist](https://gist.github.com/chriskirkland/a613cef6fef79bd00c7dd67049f111c1).

[^2]: OpenSSL metrics are not provided for HMAC 256 and AES-256-GCM because they are measured in blocks/s rather than signs/s and verify/s, so they are not directly comparable.

A few observations arise immediately:

> Content encryption is surprisingly faster than symmetric signing for both token issuance and validation.

Importantly, encryption does not provide attestation of the validity of a token.  It merely protects the claims from untrusted parties (i.e. those who don't have the shared/public encyryption key).  In our view, the credential attestation provided by token signatures is critical to the trustability of these tokens, for which encryption is not a substitute.  However, this is encouraging should the need arise for token encryption in the future.

>Token signatures are _very_ slow using RSA keys compared to elliptic curve algorithms (10-20x).

Signature verifications are faster than the presented elliptic curve algorithms, but the high cost of token signing makes the RSA family of algorithms unsuitable for our purpose.  Additionally, we tested 2048 bit RSA here whose cryptographic strength is weaker than ECDSA NIST-P256/Ed25519.  A fairer comparison would have been 3072 bit RSA (to achieve 128b strength) which performs yet worse.

> Symmetric signing algorithms are _significantly_ faster than asymmetric signing algorithms with respect to signature verification.

While signing time is roughly equivalent (within 2x), signature verification is 3-4x more expensive for the asymmetric crytography schemes we surveyed.  This is broadly recognized within the industry and several other companies use symmetric signatures for this reason (e.g. [Facebook](https://eprint.iacr.org/2018/413.pdf), [AWS](https://shufflesharding.com/posts/aws-sigv4-and-sigv4a)[^3]).  The key question at hand is **whether the tradeoff of slower performance vs increased trust with ECDSA/Ed25519 is acceptable** from a platform perspective.  To answer that, we offer a brief analysis of the expected scale and performance characteristics at play.

[^3]: Historically AWS used symmetric HMAC signing for S3 authentication but introduced ECDSA as an additional option for their multi-region offering.  This was an acknowledged performance tradeoff that was required for their architectural changes.

We estimate around [50-60k authenticate requests per second](https://app.datadoghq.com/s/59fe6c40c/j2m-pcv-yu2) are observed by the platform, on average, across web, REST API, GraphQL API, and gitauth traffic.  Considering the performance metrics show above, let's take 15k token issues/s and 10k token verifications/s as conservative lower bounds on performance[^4] for either of the EC-based asymmetric algorithms (ECDSA or Ed25519).  Assuming we adopt these stateless tokens internally for every authenticated request, then we'd need to issue a new stateless token for each request and verify it in one or more downstream services (say 2, on average).  That yields 60k issues/s and 120k verifications/s at the platform level.  This would require approximately 16 CPU cores dedicated to issuing and verifying these tokens (4 and 12 cores, resp.), which seems reasonable.  For context, a single one of our Moda partitions (`general-1-ash1-iad`) contains 721 CPU cores across it's 81 worker nodes with a [total CPU utilization under 30%](https://app.datadoghq.com/s/59fe6c40c/xf9-pt9-ffp).  As CPU utilization will be the limiting factor for client-side token verification[^5], we see no capacity concerns with this approach.

[^4]: All token issuance/verification performance metrics are per CPU core.

[^5]: For comparison, the additional network bandwith contribution will significantly less relative to current scale.  The example token provided above contains 510B and should be a reasonable stand-in for an average token.  We'll use GLB ingress/egress as a proxy for overage network bandwidth utilization in our DCs (i.e. GLB is more of a chokepoint than other pieces of the network architecture, say Kubernetes ingress).  Reusing our stated assumptions, each authenticate request would see the stateless token make 2 traversals of GLB: authnd -> public GLB, public GLB -> service A, and service A -> internal/kube-internal GLB -> service B.  At 120k GLB traversals/s, that means an additional 58 MB/s would be introduced to our GLB layer.  The total network transit observed by GLB clusters across all sites is roughly 110 GB/s.  So the additional requirement constitutes around 0.05% of current GLB bandwidth.

In addition to ECDSA with NIST-P256, which was our cryptographic choice for [GitHub Mobile 2FA](https://github.com/github/authentication/blob/59a8a803747e0ba0dba7f8dce8bbf9d2f1d62a1f/docs/adr/0007-GH-mobile-2FA-signing.md), we also examined [Ed25519](https://ed25519.cr.yp.to/index.html).  Ed25519 is growing in popularity and claims to offer faster signature verification relative to ECDSA[^6] as well [safer cryptographic properties](https://safecurves.cr.yp.to/).  Despite being a newer method, Ed25519 appears to have sufficient support in the languages broadly used in our Platform ([Ruby](https://github.com/jwt/ruby-jwt), [Go](https://pkg.go.dev/gopkg.in/square/go-jose.v2#readme-supported-key-types), [Rust](https://github.com/Keats/jsonwebtoken), [ReactJS](https://github.com/panva/jose)).  However, Ed22519 is not FIPS compliant and would not be eligible for use in GHAE[^7].  In order to provide a consistent platform experience across Dotcom, GHAE, and GHES, we must therefore favor ECDSA as the cryptographic signing algorithm.

[^6]: Our observations saw mixed results, but the performance benefit of Ed25519 is confirmed by [ECRYPT](https://bench.cr.yp.to/results-sign.html) with roughly 41% fewer clock cycles for signature verification (2020 Intel Core i7-1165G7; 4 x 2800MHz).

[^7]: See "Digital Signatures" under [Appendix A of FIPS 140-2](https://csrc.nist.gov/csrc/media/publications/fips/140/2/final/documents/fips1402annexa.pdf).  Only RSA, DSA, and ECDSA are compliant signature algorithms.

## Consequences

Because the proposed stateless tokens are signed and not encrypted, the token claims use a plaintext encoding which can be read by anyone.  As the tokens are only planned to be visible inside of GitHub datacenters, this is acceptable. Additionally, this means services provided with the statless token directly (e.g. through an `Authorization` header on an inbound RPC) could use the token without first verifying it with the `authnd` client.  Our choice of attribute encoding and token format should seek to discourage this behavior as much as possible.  Though we do not intend to encrypt initially, our above experiments verified that symmetric encryption is reasonably performant and could be used in the future should the need arise.

As mentioned above, these tokens will be significantly larger than our user-facing credentials (by roughly 5-10x). This will result in an increase in the size of internal RPC requests.  We will want to work closely with the networking and Moda teams over time to monitor the effect on network bandwidth.
