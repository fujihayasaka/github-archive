# 21. Which User Data Should be Owned by Authnd

Date: 2021-01-08

## Status

Accepted

## Context

The authentication team is beginning work on an [epic](https://github.com/github/authnd/issues/399) to expose
oauth tokens through the Authnd service. One of the goals with authnd is to decouple it and data that it
owns from `mysql1` to allow it to independently scale. As we have begun a solution for replicating the data
that is relevant for OAuth tokens from `mysql1` to the `authnd` database, we want to be intentional about
which data from the `users` table should fall under the scope of authentication vs authorization. As part of
the wall-e work the team wrote an [ADR](./0014-attribute-schema.md#users) that outlined an attribute schema
for OAuth token responses, which includes:

```
actor.id (int64): an int64 matching the id of the User for whom the token was issued.
actor.type (string): user
user.spammy (bool): true if the User is spammy, otherwise not present.
user.login (string): a string with the login of the authenticated user
user.site_admin (bool): true if the User is a site admin, otherwise false.
credential.type (string): the string oauth_access_token.
credential.scopes (list of string): a list of scopes associated with the access token or not present if there are no scopes.
application.id (int64): an int64 matching the application id assigned to the token.
organization.sso_authorized_ids (list of int64): a list of organization IDs with SSO credential authorizations for this token.
```

The attributes of note to this ADR are those related to `user`: `spammy`, `login`, `site_admin`. In
the [existing dotcom logic](https://github.com/github/github/blob/2ceeb92dd3a05285e310813feec0f52daa09a3a8/lib/github/authentication/default.rb#L117-L143) which validates an OAuth token, it also checks whether the
user is suspended.

We have a [feature](https://github.com/github/authnd/issues/507) as part of this OAuth token epic to create
tables in the authnd database that represent authentication data.

## Decision
The authentication response defines `user.site_admin` as an attribute that should be returned, however we think this attribute is more appropriate for a client of authzd define in their policies if that is something
required. This is because `user.site_admin` requires the `abilities` table in which a user must be a member
of the `Employees` or `Interns` team and have a `gh_role` of `staff`. These describe permissions rather
than identity.

We have identified the following tables that need to be replicated from mysql1 to authnd for performance
purposes, but this does not imply ownership of the data.

```
users
oauth_accesses
oauth_authorizations - note (2021-5-3): originally thought to be needed for oauth token scopes, oauth_accesses.raw_data made this table unnessesary
organization_credential_authorizations
oauth_applications
integration_installations
```

The following indicates which columns we need to replicate from mysql1 to authnd.

### users
Contains data that identifies the user to which oauth tokens belong. It's TBD if authnd will own creation of these users in the future.

We decided that `user.spammy` is an attribute that will not be returned by authnd, and will be resolved by
authzd. So, we will remove that from the authnd response and not replicate it with user data.

#### Columns to Replicate
```
id
login
created_at
updated_at
suspended_at
```

### oauth_accesses
Contains both PAT and OAuth (Application) tokens. Authnd may eventually own this table, but it will be
replicated to authnd for performance purposes.

#### Columns to Replicate
```
id
user_id
application_id (references integration_id, oauth_application_id, or 0 for PATs)
authorization_id (references oauth_authorizations table)
application_type (OAuthApplication or Integration)
hashed_token (sha256 hash of token)
token_last_eight
created_at
updated_at
accessed_at
expires_at_timestamp
```

### organization_credential_authorizations
Determines which Organization SSO Authorized IDs should be returned with the authentication response.
Authnd may eventually own this table, but it will be replicated to authnd for performance purposes.

#### Columns to Replicate
```
id
organization_id
credential_id
credential_type
created_at
updated_at
revoked_at
revoked_by_id
```

### oauth_applications
Used for OAuth Applications (not GitHub Apps). Examine state to determine suspension state.
Authnd may eventually own this table, but it will be replicated to authnd for performance purposes.

The following comment snippet from dotcom represents the integer values for state
```
:active           - Active and allowed to have oauth accesses (default).
:suspended        - Suspended from generating oauth accesses due to abuse
                    or security concerns.
:pending_deletion - In the process of being deleted in a background job.
                    This state is largely for the UI.
enum state: { active: 0, suspended: 1, pending_deletion: 2 }
```

#### Columns to Replicate
```
id
name
user_id
state
created_at
updated_at
```

### integration_installations
Used to determine GitHub App exists and suspension state.
Authnd may eventually own this table, but it will be replicated to authnd for performance purposes.

#### Columns to Replicate
```
id
integration_id (PK of integrations (not replicated). Join this column to `application_id` of `oauth_accesses` for GitHub Apps only)
integration_version_id
user_suspended_by_id
user_suspended_at
integrator_suspended_by_id
integrator_suspended_at
created_at
updated_at
```
