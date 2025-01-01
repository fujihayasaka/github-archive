# Secret Scanning Flow for Project Mint Tokens

## Overview

1. [Secret Scanning agent](https://github.com/github/hypercredscan) (SS) detects supposed leaked token in a repository in dotcom (done in per-repository batches).

2. SS does client-side verification to ensure the tokens were issued by `authnd` (i.e. regexp matching and checksum validation).

3. If the repository is public, Secret Scanning immediately revokes the token:

    a. A call is made to the `RevokeCredential` API in `authnd` to revoke the token

4. If the repository is private, Secret Scanning takes the following steps:

    a. A call is made to the `ValidateCredential` API in `authnd` to retrieve the user ID.

    b. SS issues a hydro message which is received by a processor in Dotcom. That processor send a mailer to notify owner of the offending commit. Importantly, the owner of the token is not notified currently.

    b. SS calls the `RevokeCredential` API in `authnd` to revoke the token.  This only happens for Microsoft and GitHub repositories today, but will expand to private repos in the future.

5. In either case, after the token is revoked, `authnd` publishes a message to Hydro containing information about the revoked token (1 token per message).  If the `CredentialExposed` reason is used, the hydro message will include an indication that the generic mailer should not be sent (e.g. `SendMailer: false`).

6. A background job (`ApplicationJob`) in dotcom reads from the Hydro topics and sends a mailer notification to the affected user.  This flow is there for notifying users for tokens revoked by anything other than SS.  For SS, this job will ignore the hydro messages and will not send notifications to the user.

### API Details

**`RevokeCredential`** ([spec](https://github.com/github/authnd/blob/d75f0d3fe6b6e90cf22f6f5acd704655cbed6693/proto/authentication/v0/revoke.proto))
- A batch API to revoke credentials by ID or credential.  For most internal usage, the credential ID is used.  For SS, the raw credential is used.
- A maximum batch size of 100 is allowed.
- A hydro notification and user-facing audit event are issued for each authnd-issue credential (i.e. PATv2).
- A `reason` attribute must be provided in the request indicating the reason why the credential is being revoked.  A special reason, `CredentialExposed`, will be used by secret scanning for revocation caused by exposure and subsequent detection by secret scanning.

**`ValidateCredential`** (In progress)
- A batch API to validate credentials and return a limited subset of token attributes
- Currently returns the following attributes:
  - `actor.id`
- A maximum batch size of 100 is allowed.
- A token validation request is more limited in scope than a full authentication request, and it's results should not be as input for authorization decisions.