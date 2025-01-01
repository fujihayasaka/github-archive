# 14. Authentication response v0 attribute schema

Date: 2020-07-31

(Retroactively numbered - This was a design doc from the Wall-E experiment that has been absorbed in as an ADR)

Date: 2021-1-29: Ammended attributes to align with service intentions

## Status

Accepted

## Context

Authnd and authzd are tightly coupled, the output of a successful authnd response becomes (with slight modification) the input of an authzd request.
The primary form of interchange are attributes, a set of typed key/value pairs using the [authzd Value type][1].
This document describes the schema for attributes returned from a successful credential validation via authnd.

## Notes

### Successful authentication

Attributes are only returned on a successful authentication request.
If the authentication is unsuccessful the attribute list will be empty.
Callers should not use the size of the returned attribute list as proxy to determine if a request was successful or not.

### Attribute attributes

Although attributes are treated as a list when transmitted over protobuf, authnd considers attributes to be a set.
This has two ramifications:

1. AuthenticationResponse attribute keys are unique.
An attribute key will not appear more than once in the AuthenticationResponse attribute list.
2. The ordering of AuthenticationResponse attributes is not defined.
Consumers should avoid assuming a particular attribute appears at a constant index in the attribute list.

## Authentication Inputs and Their Respective Outputs

### LoginPassword

LoginPassword is the eponymous login (username) and password pair.

- `actor.id` (`int64`): an int64 matching the id of the User corresponding to the login / password pair.
- `actor.type` (`string`): `user`
- `user.login` (`string`): a string with the login of the authenticated user
- `credential.type` (`string`): the string `login_password`.

### SSHPublicKey

SSHPublicKey represents an SSH public key registered to a User.

- `actor.id` (`int64`): an int64 matching the id of the owner of the public key with a matching fingerprint.
- `actor.type` (`string`): `user`
- `publickey.notverified` (`bool`): `true` if the public key is has not been verified or the verification date is in the future, otherwise not present.
- `user.login` (`string`): a string with the login of the authenticated user
- `credential.type` (`string`): the string `ssh_public_key`.
- `organization.sso_authorized_ids` (list of `int64`): a list of organization IDs with SSO credential authorizations for this token.

### OAuthAccessToken

OAuthAccessToken represents an OAuth 2.0 access token.
OAuth tokens can represent several kinds of actors.
The attribute list returned depends on the actor for whom the token was issued.

// derrived from https://github.com/github/github/blob/c0f30d76903adcd5c33ec5cc5cf75fe052630667/app/models/permissions/enforcer.rb#L134

- `actor.id` (`int64`): an int64 matching the id of the User for whom the token was issued.
- `actor.type` (`string`): `User`
- `user.login` (`string`): a string with the login of the authenticated user
- `credential.type` (`string`): (varies) the type of token -  `PersonalAccessToken`, `OauthAccessToken` `UserToServerToken`.
- `credential.scopes` (list of `string`): a list of scopes associated with the access token or not present if there are no scopes.
- `application.id` (`int64`): an int64 matching the application id assigned to the token, this value isn't present when `credential.type` is `PersonalAccessToken`.
- `application.type` (`string`): (varies) the application assigned to the token, `OauthApplication`, `GithubApplication`, this value isn't present when the `credential.type` is `PersonalAccessToken`.
- `organization.sso_authorized_ids` (list of `int64`): a list of organization IDs with SSO credential authorizations for this token.

### InstallationToken

InstallationToken represents an 40 character authentication token beginning with `v1.`.
They are used for server to server authentication for installations and are associated with Github Applications.

// derrived from https://github.com/github/github/blob/c0f30d76903adcd5c33ec5cc5cf75fe052630667/app/models/permissions/enforcer.rb#L134

- `actor.id` (`int64`): an int64 matching the installation id of the token.
- `actor.type` (`string`): `ScopedIntegrationInstallation` if the bot is a `ScopedIntegrationInstallation`, otherwise `IntegrationInstallation`. "GitHub App actors" can also be of type `Integration` and `SiteScopedIntegrationInstallation` in relation to authzd policies.
- `installation.integration.id` (`int64`): an int64 matching the id of the Integration of the installation.
- `installation.parent.id` (varies): an `int64` matching the parent IntegrationInstallation ID for ScopedIntegrationInstallations, not set for other actor types.
- `installation.target.id` (`int64`): The id of the target that the installation is installed on.
- `installation.target.type` (`string`): The type of the target that the installation is installed on.
- `credential.type` (`string`): the string `ServerToServerToken`.
- `credential.scopes` (list of `string`): a list of scopes associated with the access token or not present if there are no scopes.

[1]: https://github.com/github/authzd/blob/master/proto/authz.proto#L52
