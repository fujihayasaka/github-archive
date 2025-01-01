# 32. Updating the PATv2 Token Prefix

Date: 2021-11-15

## Status

Accepted

Supersedes [28. PATv2 Token Format](0028-pat-token-format.md).

## Context

As part of [Project Mint](https://github.com/github/authnd/issues/1011), we introduced support for issuing tokens from `authnd` to support the PATv2 initiative.  The format of those tokens was formalized in a [previous ADR](0028-pat-token-format.md).  The prefix for those tokens, `gh1_`, deviates from the standard set forth by earlier [token prefix unification efforts](https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/).   That standardization effort was undertaken by the Secret Scanning team with the purpose of leading the industry toward more recognizable and understandable token formats.

The tangible goals for this earlier standardization effort at was to make GitHub tokens:
1. Recognizable as tokens issued by GitHub (prefix starts with `gh`).
2. Distinguishable by token type in a way that's human readable (next character is `p` for personal access token).

However, these earlier efforts were heavily constrained by concerns about increasing token length, even slightly.  Given that we do not have the same concern with Project Mint, we are free to explore new token prefixes that simultaneous align with the spirit of the earlier goals while maintining the flexibility to adopt new use cases as they arise.

## Decision

The token format for PATv2 is adjusted to add a new `<type>` section:

```
<prefix>_<type>_<header>_<random><checksum><identifier>
```

The `<prefix>` will be adjusted from `gh1_` to `github_`.  The `github` prefix will be reserved exclusively for `authnd`-issued tokens; no tokens currently issued by Dotcom will be retrofitted to use this prefix in the future.  As a result, secret scanning will be able to immediately identify tokens issued by `authnd` from the prefix alone. This increases the length of the prefix from 3 to 6 characters.

The `<type>` section will contain a 3 character, human-readable description of the token type. The `<type>` will be `pat` for PATv2.  Should new token types be issued by `authnd` in the future, new type descriptors would be added (e.g. `oat` for OAuth tokens).  This adds an additional 4 characters to the token length.

The `<header>` will be updated to begin with the token version, `1` in this case. Previously, the token version was represented in the prefix (`gh1`).  This increases the length of the header from 21 to 22 characters.

The remaining portions of the token format will remain unchanged.

These changes help us to align with the core mission of secret scanning while  maintaining the flexibility designed into previous PATv2 token format iterations.

Below is an example token (just garbage data for illustration):
```
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
```

Originally, we considered alternatives using variations of the standardized PAT prefix, `ghp`, with the additional token version:

1. `ghp1_` - This contains the token type characters but ultimately deviates from the prefix standard in much the same way as `gh1_`.
2. `ghp_1<header>_` - This contains the standard PAT prefix but elides the token version onto the header section. Aesthetically, this is an appealing approach as it groups human-readable and server-specific information together.  However, this approach makes it difficult for secret scanning to differentiate between PATv1 and PATv2 tokens.  As the prefix are the same, we would need to rely on either the token length or number of underscore-delimited segments to differentiate the tokens. Because of the variety of use cases these Mint Tokens may adopt in the future, both of those approaches were deemed too brittle.
3. `ghp_1_` - This contains both the standard PAT prefix and token version in a way that's flexible for `authnd` and easily detectable by secret scanning.  However, the additional `1_` prefix is aesthetically unappealing in a way that wasn't acceptable for a token format which we hope sticks.

## Consequences

The total token length is increased from 85 to 93 characters.  Our [previous external communications](https://github.blog/changelog/2021-03-31-authentication-token-format-updates-are-generally-available/) have notified integrators to prepare for tokens of up to 255 characters, so there should be no storage concerns.  However, the Apps team is actively iterating on the design for PATv2 web UI, and the increase in token length may affect the compactness of those designs.

The secret scanning team will need to adjust the regular expressions they use to differentiate credentials issued by Dotcom and `authnd` to respect the new prefix.

Because we're deviating from the prefix sets we've previously announced, there will need to be a new round of external communication to avoid confusion.  The Apps team has agreed to publish a blog post with those details sometime around/before the GA of PATv2.