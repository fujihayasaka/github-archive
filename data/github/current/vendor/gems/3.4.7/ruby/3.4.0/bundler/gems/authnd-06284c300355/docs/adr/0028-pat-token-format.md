# 28. PATv2 Token Format

Date: 2021-07-28

## Status

Accepted

## Context

As part of [Project Mint](https://github.com/github/authnd/issues/1011) we need to select a specific token format to use.
We can either use a standardized format, like [JWT](https://jwt.io) or [PASETO](https://paseto.io/), or design our own format.
The token format we select must meet a few requirements:

1. The token must be appropriate to display to a user in UI.
    * Since a primary use case of these tokens is PATv2, we expect to display these tokens to a user.
    * This doesn't *mandate* that the token be short, but it does mean we should make concious decisions about token length.
    * It also means we should consider factors like "double-clickability" (can the entire token be selected when any portion of the text is double-clicked).
2. The token should be equipped to store some metadata to aide in sharded storage and avoiding replication lag
    * Sharding by actor identity (User ID, etc.) seems an appropriate default approach.
3. Tokens must be revocable, since they can be long-lived and non-expiring.
4. Tokens should be easily detectable by secret scanning tools.
    * Using a vendor-specific prefix allows us to write fairly simple Regexes to match against tokens.
    * Some form of externally-verifiable hash/signature would allow secret scanning tools to gain additional confidence that a candidate token is likely a GitHub token.

Storing metadata in a token comes with a risk that relying parties will _use_ that data rather than calling authnd.
If a token stores the actor identity, for example, a relying party may choose to use that to authenticate the user.

Standardized formats like JWT and PASETO give us the ability to store metadata within the token but come at a significant size cost.
From our initial investigations, it would be difficult to get a standards-compliant JWT or PASETO token below 200 characters long.
Much of this is due to the size of the signature.
A SHA256 HMAC requires at least *43 characters* in Base64 (if you truncate padding).
Asymmetric signatures (which would be necessary to provide many of the benefits of trustable metadata in our tokens) are even larger, an ES256 signature on a JWT token is around *85 characters*, and an RS256 signature is even larger (over *300 characters*).

PATs make up a relatively small portion of our current data storage needs for tokens (8 Million rows out of 100 Million in `oauth_accesses`).
Despite being <10% of our stored tokens, Personal Access Tokens make up a substantial portion of our API authentication requests (~45% of _authenticated_ requests, ~35% of all requests).
OAuth tokens are generated and regenerated via automation and thus have significantly higher impact on our data storage.
However, this **also** means OAuth and GitHub app tokens are less sensitive to token length and could be replaced with a standards-compliant signed token that stores much more metadata.

New token formats come with high risk.
Rolling a new token format is perhaps only a single step down from the risk of rolling your own cryptography.
We should take care to only use a custom token format where absolutely necessary and avoid using data in that token format for trust decisions.

## Decision

For PATs and any future tokens for which size is a concern, we will use a simple token format that leans _heavily_ on the existing model of looking up random values.
For future OAuth tokens and any tokens intended to be exchanged without user intervention (i.e. without copy-pasting), we will use standardized formats (JWT/PASETO, details to be decided later as needed).

The proposed format for PATv2 is the following:

```
<prefix>_<header>_<random><checksum><identifier>
```

Where:

* `<prefix>` is a plain-text prefix to identify the token, we propose the value `gh1` in this ADR, but this could also be made flexible.
  * We should use a prefix that is different from the current prefixes in use (`ghp`, `gho`, etc.) so that we can easily identify these new tokens.
* `<header>` is an arbitrary payload used **only** by authnd to identify token version, type and sharding information.
  * We plan to store a token "type" (which also serves as a version) and actor identity (for sharding).
  * The encoding of this format is not yet defined, but will only use alphanumeric (upper and lower-case letters) characters.
* `<random>` is a series of 43 random alphanumeric (upper and lower-case letters) characters. This is equivalent to just over 256-bits of randomness.
* `<checksum>` is a SHA256 hash of the entire string up to that point, encoded in Base32 and truncated to 8 characters.
  * This encoding uses the first 40 bits of the SHA256 hash.
  * The only purpose of this checksum is for secret scanning tools to confirm the token is a well-formed GitHub token, to reduce false positives.
* `<identifier>` is 8 random alphanumeric (upper and lower-case letters) characters used to identify the token to the user
  * This value would be stored in plaintext alongside the hashed token in our database
  * This value would be returned to callers when a token is issued or authenticated and recorded in logs for support purposes and to notify users which token performed certain actions.
  * By using a purely random value that is not associated with or derived from the "token" portion, this value does not compromised the entropy of the token

The total token length will be 85 characters, which breaks down into the following segments:

* The `<prefix>` is 3 characters
* The `<header>` is 21 characters
* The `<random>` is 43 characters
* The `<checksum>` is 8 characters
* The `<identifier>` is 8 characters

Adding these up, plus the 2 underscore separators, yields: `3 + 21 + 43 + 8 + 8 + 2 = 85`.
However, the exact distribution of characters between `<header>` and `<random>` may be adjusted over time as we adjust to what we see happening in the wild.
Consuming services at GitHub should make no assumptions about the content of the token, except for the `<checksum>` and how it is computed.
In addition, the authentication team will provide libraries in Ruby and Go for performing checksum computation.
Consuming services _should_ avoid any manual analysis of the token and **must never** make their own authentication decisions using the token content.

The entire token will contain only alphanumeric characters, and the `_` character.
Limiting the token to this character set ensures tokens can be transmitted in many different protocols, as well as retaining the property of being "double-clickable" (double clicking on the token selects the entire token)

The exact format of the `<header>` is reserved for use by authnd and will be used only to provide hints to look up the `<random>` value.
In essence, the `<random>` section **is the token**, and all the additional data is usable only for distinguishing which shard to look it up in.

Below is an example token (just garbage data for illustration):

```
gh1_2xkl2MztKWfG69hDURnjl_ZN5hE1K77FJnXznZbXgPHA2GIodRKMWqFoG6wORij4M5N5hE1K7uHbLL8KD
```

This example token contains a 22 character `<header>`, which is more than we need to encode the versioning, and sharding metadata we anticipate needing well into the future.
If we find we don't need this data, we can also use it to expand the `<random>` and increase entropy of the token.
The `<header>` is padded out to this length to ensure that we have some capacity to adjust the content of the `<header>` without impacting users who are storing tokens in fixed-length database columns.

When a token is generated, the **entire payload** (including the header, checksum, identifier, etc.) is hashed and stored in the database.
To be valid, the entire payload must be presented to authnd unmodified.
External services **must** treat these tokens as completely opaque strings, with the one limited exception of validating the `<checksum>` value **solely** to identify tokens for secret scanning purposes.

## Consequences

By sticking with an unsigned random token for authentication, we must perform a database lookup for every token authentication.
However, PATs will be stored separately from OAuth and other tokens, which allows us greater flexibility in how we distribute load and data storage.
In addition, we can use the `<header>` segment to encode metadata to use for sharding.
Since the entire hashed token payload must exist in the database to be authentic, using the header data to select a shard would not compromise the security of the token.

The original Mint design document discussed using issuance timestamps to avoid replication lag issues, however these tokens do not encode that data and cannot use that optimization.
However, by focusing on PATs and storing the data in a much lower-traffic data store, we will likely be able to avoid replication lag issues.
We could also have a cluster-wide "cache" of recent tokens, and/or store issuance time in the `<header>`, if that becomes an issue.

Our trust model requires that these tokens be transmitted to authnd for validation.
This means we cannot perform any authentication decisions until the token is given to authnd.
For example, we cannot check the rate limit for a user, or the expiry date of the token until we have validated it against authnd.
This trade-off is necessary in order to retain a token that is compact and avoids the significant (and necessary) overhead associated with the standard formats.

In general, the act of moving the most-used and least-modified token format to it's own data store gives us enough benefit that we don't believe complicated scaling techniques are needed here.
However, expanding the token to 85 characters and storing some shardable metadata in the token gives us that option in the future, if our assumptions turn out incorrect.

This token format will likely **not** be sufficient for migrating tokens like GitHub App and OAuth tokens.
Those tokens are generated and used quickly, by automation, and suffer from customer-reported replication lag issues today.
By simplifying the token format for this PATv2 project, we will likely need a second format for these tokens.
However, there is much more precedent in the industry for these non-user-facing tokens to use standard formats such as JWT.
We can adopt standard formats when designing those tokens and reduce the risk of storing much more metadata in the token itself.

Since the token, at 85 characters long, is just over double the size of the current token (40 characters), we will make public announcements to prepare integrators.
Coupling this increase in token length to a new token launch like PATv2 gives us a better opportunity to gather customer feedback on the actual impact this will have.
In the event that customer feedback is sufficient to convince us that we need to return to the 40 character token length, we still have options for sharding (via the token itself) and other optimizations.
