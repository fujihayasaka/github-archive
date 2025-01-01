# Changelog

## v0.22.0

* Changes `SignedAuthToken.Version` type from `uint64` to `string` in the client actor model, to add support for token versions like `hex` or `session`.
  * The attribute type returned from the RPC is still an `uint64`, since authnd server still only support version `3`.

## v0.21.4

* Fixes parsing for user-to-server token, to have the correct application type of Integration.

## v0.21.3

* Fixes actor parsing when legacy pats and fine grained pats actor is received with an attribute for expires_at or issued_at set to nil.

## v0.21.2

* Added `HasExpiredAuthRequest` on response from `MobileDeviceManager.FindActiveDeviceAuth`.

## v0.21.1

* Adds opts to IdentityManager client

## v0.21.0

* Updates S2S token bot actor parsing such that it doesn't require application attributes and changes `NewBotActor` to receive an `ApplicationContext` pointer.

## v0.20.1

* Fixes `IsAuthenticatedViaSSHPublicKey` to return true for user public keys _and_ deploy keys.
* Fixes typo for `InstallationType` (`IntegrationTypeSiteScopedIntegrationInstallation` -> `InstallationTypeSiteScopedIntegrationInstallation`)

## v0.20.0

* Changes `AccessIDAttribute` variable to `ProgrammaticAccessIDAttribute` so that it's clear it's not meant to be used for oauth access ID
  * Addresses some bugs in the actor parsing related to `access.id` attribute assertions due to confusion above
* Adds `CredentialTypeSignedAuthToken` back as a credential type (was removed accidentally sometime after 0.18.1)
  * Adds support for parsing a signed auth token authentication attempt into an `Actor`
* Removes `DeployKey` credential type - this isn't a credential type returned by authnd (it's always `CredentialTypeSSHPublicKey`)
* Adds the ability to retrieve the original attributes back off the Actor model
* Adds a helper function on the `Actor` model for retrieving SSH public key context off of the actor (for user keys and deploy keys)

## v0.19.8

* Add Discovery Document and JWKS api endpoints for OIDC and improvements to `IdentityManagerService`

## v0.19.7

* Updates `ActorFromAuthenticateAttributes` to support `map[string]interface{}` to support constructing actors from the client's `AuthenticateResponse`.

## v0.19.6

* Updates actor parsing to parse the `IntegrationInstallation` vs. `ScopedIntegrationInstallation` vs. `SiteScopedIntegrationInstallation` correctly.

## v0.19.5

* Updates `NewExchangeTokenVerifier` to accept an optional list of `Option` enable injection of a statter via `WithStatter`. This enables observability for both clients and developers of authnd.
  * New stats include:
    * `authnd.client.token_verifier.verify_token_ns` - the duration of `VerifyToken` calls.
    * `authnd.client.token_verifier.public_key_loaded` - instances of public keys loaded during `NewExchangeTokenVerifier`, includes the `kid` to enable safe rotation of the server signing key.
    * `authnd.client.token_verifier.unexpected_kid` - instances of `VerifyToken` calls on tokens for which the `kid` encoded in the header does not match a public key loaded by the `ExchangeTokenVerifier`.
  * If your statter was initialized with a prefix, all `ExchangeTokenVerifier` stats will be duplicated without the prefix to simplify `authnd` observability.

## v0.19.4

* Updates the `Actor` model package dir to `identity` to avoid variable naming collisions.
  * Adds some new helper methods on the `Actor` interface to help with checking the credential type.

## v0.19.3

* Introduces the `IdentityManagerService` which accepts a token exchanged using the `IssueIdentityToken RPC` and signs it using a private key.
  * `NewManagerServer` will return an error unless the required secrets `IDENTITY_PRIVATE_KEY`, `IDENTITY_PUBLIC_KEY`, & `IDENTITY_CERTIFICATE` are present.

## v0.19.2

* Introduces a new, experimental `Actor` model that can by instantiated from response attributes or a token exchange token.
  * Provides `ActorFromAuthenticateAttributes` and `ActorFromExchangeToken`

## v0.19.1

* Introduces the `ExchangeTokenVerifier` which accepts a stateless token exchanged using the `TokenExchanger RPC` and produces a bundle of authentication Attributes.
  * `NewExchangeTokenVerifier` will return an error unless the `TOKEN_EXCHANGER_PUBLIC_KEYS` secret is federated into your app's Vault.

## v0.19.0

* Introduces the `TokenExchanger` RPC service
  * Adds the `ExchangeToken` RPC which accepts an access token and produces a signed JWT (i.e. Transparent Authentication token) contains claims equivalent to attributes returned by the `Authenticate` RPC.

## v0.18.3

* Added new RESULT_FAILED_APPLICATION_OWNER_SPAMMY result type (#2634)

## v0.18.2

* Updates google.golang.org/protobuf from 1.28.0 to 1.33.0 (#2363)

## v0.18.1

* Adds a `WithTenantSlug` request option to all methods on the `Authenticator` and `CredentialManager` as an alternative to `WithTenant` from the previous release.  This provides a simple way to pass the tenant slug (`X-GitHub-Tenant`) for a RPCs to authnd in Proxima.
  * Either the tenant slug or both the ID and shortcode are required for requests in Proxima.
  * Tenant headers are ignored in GHES/GHEC/Dotcom.

## v0.18.0

* Adds a `WithTenant` request option to all methods on the `Authenticator` and `CredentialManager`.  This provides a simple way to pass the tenant ID (`X-GitHub-Tenant-ID`) and shortcode (`X-GitHub-Tenant-Shortcode`) for a RPC to authnd in Proxima.
  * Tenant headers are required in Proxima and ignored in GHES/GHEC/Dotcom.

## v0.17.0

* Updates protos to add support for 2 new ways of revoking mobile device keys (by oauth access id and by mobile device key ids).

## v0.16.0

* Adds the `CredentialManager.IssueToken` method with support for issuing user- and session-scoped tokens.
  * Known limitations with attributes:
    * Only flat hashes with string keys are supported.
    * Time objects are not supported as values.

## v0.15.0

* Adds auto-instrumented traces to all outbound requests
* Deprecates `WithTracer` method which allow injecting a custom tracer, which predates the internal otel migration effort.

## v0.14.5

* Added `access_id` and `expires_at` to the verify credentials response.

## v0.14.3

* Added constants for well-known response attributes: `actor.type`, `application.type`, and `credential.type`.

## v0.14.2

* `MobileDeviceManager.FindDeviceKeyRegistrations`, now returns `OauthAccessId` with the response.

## v0.14.1

* Updates `VerifyCredentials` to return a `result` which will containing success or a failure reason.

## v0.14.0

* Introduced `MobileDeviceManager.RevokeDeviceKeys`, which can be used to revoke all device keys given a `UserId`.

## v0.13.1

* `MobileDeviceManager.RequestDeviceAuth` supports `2fa_password_reset` as a `type`.

## v0.13.0

* No changes 🎉

## v0.12.1

* Added `type` on response from `MobileDeviceManager.FindActiveDeviceAuth`, used to differeniates the different mobile auth request types.

## v0.12.0

* Added `type` to the `MobileDeviceManager.RequestDeviceAuth` request.
  * Default value is `2fa_login`.
  * Supported values are: `['2fa_login', 'device_verification']`.

## v0.11.6

* No changes 🎉

## v0.11.5

* No changes 🎉

## v0.11.4

* No changes 🎉

## v0.11.3

* No changes 🎉

## v0.11.2

* Adds `CompleteDeviceAuthResponse_RESULT_ALREADY_APPROVED` and `CompleteDeviceAuthResponse_RESULT_ALREADY_REJECTED` enums to the `MobileDeviceManager.CompleteDeviceAuth` response.

## v0.11.1

* Removing support for prototype `V0Token` token previously issued by Authnd.
* CredentialManager and Authentication APIs no longer accept V0 tokens.
* V0 tokens are no longer recognized by `IsAuthndToken` and `IsChecksumValid` helper methods.

## v0.10.0

* Added `VerifyToken` for verifying tokens issued by Authnd.  Currently only `ProgrammaticAccessTokens` are supported. This does not constitute authentication. Its primary purpose is gather a limited set of attributes associated with the token during secret scanning.
* Updates `TokenRegex` to match the new `github_pat_1` token prefix for `ProgrammaticAccessTokens` ([ADR](https://github.com/github/authnd/pull/1335)).

## v0.9.6

* Added `HasValidChecksum` for determining if a given authnd-issued token's checksum is valid.  This does not constitute authentication. Its primary purpose is to filter authnd tokens during secret scanning.
* Added a `TokenRegex` constant that pattern matches all authnd-issue tokens.
* Updates `IsAuthndToken` to use `TokenRegex`. Previously, this function only used prefix matching.

## v0.9.5

* Added `SkipChallenge` to the `MobileDeviceManager.RequestDeviceAuth` request. This can be used to skip the challenge prompt for mobile device auth approval.
* Added `ChallengeRequired` on response from `MobileDeviceManager.FindActiveDeviceAuth`. This can be used to determine if the challenge needs to be used when signing the payload for mobile device auth approval.

## v0.9.4

* Introduced `MobileDeviceManager.FindDeviceKeyRegistration`. This function can be used find the device key registration associated with a `UserId` and `OauthAccessId`.

## v0.9.3

* `Authenticator.Authenticate` now returns the token's configured expires at time for `ProgrammaticAccessTokens`.
* `Authenticator.Authenticate` now returns the `user.login` attribute for `SignedAuthTokens`.
* `MobileDeviceManager.RegisterDeviceKey` now revokes all active device auth keys associated with the provided OAuth Access ID before registering the provided key.
* `MobileDeviceManager.RevokeDeviceKey` now revokes all active device auth keys associated with provided the OAuth Access ID.

## v0.9.2

* `MobileDeviceManager.FindDeviceKeyRegistrations`, now returns `CreatedAtTime` & `ExpiresAtTime` with the response.

## v0.9.1

* `MobileDeviceManager.RequestDeviceAuth`, now returns an `ExpiresAtTime` with the response.

## v0.9.0

* Introduced `MobileDeviceManager.RegisterDeviceKey`, which registers a public key for a mobile device that can be used for authentication or recovery requests.
* Introduced `MobileDeviceManager.RevokeDeviceKey`, revokes a public key for a mobile device so that it can no longer be used.
* Introduced `MobileDeviceManager.FindDeviceKeyRegistrations`, which can be used to fetch device key registrations associated with a user.
* BREAKING CHANGE: `MobileDeviceManager.GetDeviceAuthStatus` now requires UserId in the protobuf request.
* BREAKING CHANGE: `MobileDeviceManager.FindActiveDeviceAuth` now requires OauthAccessId in the protobuf request.
* BREAKING CHANGE: `MobileDeviceManager.CompleteDeviceAuth` now requires OauthAccessId in the protobuf request. DeviceId no longer exists.
* BREAKING CHANGE: `MobileDeviceManager.RegisterDevice` was removed in favor or `RegisterDeviceKey`.
* BREAKING CHANGE: `MobileDeviceManager.RevokeDeviceAuth` was removed in favor or `RevokeDeviceKey`.
* BREAKING CHANGE: `MobileDeviceManager.UpdateDevice` was removed.

## v0.8.0

* Introduced `MobileDeviceManager.CompleteDeviceAuth`, which can be used to approve or reject a device auth request.

## v0.7.0

* BREAKING CHANGE: Added request argument `user_id` to `MobileDeviceManager.UpdateDevice`, which updates attributes associated with a mobile device.
* BREAKING CHANGE: Added request argument `user_id` to `MobileDeviceManager.RevokeDeviceAuth`, which revokes the authentication credential linked to a mobile device.

## v0.6.0

* BREAKING CHANGE: `MobileDeviceManager.RegisterDevice` required request proto fields have changed. Now requires new fields used to validate the provided public keys.
* BREAKING CHANGE: `MobileDeviceManager.UpdateDevice` required request proto fields have changed. Now requires new fields used to validate the provided public key.
* Introduced `MobileDeviceManager.RequestDeviceAuth` to initiate a mobile device authentication attempt.
* Introduced `MobileDeviceManager.GetDeviceAuthStatus` to retrieve the status of a device auth request.
* Introduced `MobileDeviceManager.FindActiveDeviceAuth` to find an active device auth request for a given user.

## v0.5.0

* 💥 **Breaking Change**: Removed deprecated `OAuthAccessToken` credential type.
* Introduced `MobileDeviceManager.RegisterDevice`, which registers a mobile device associated with a user.
* Introduced `MobileDeviceManager.UpdateDevice`, which updates attributes associated with a mobile device.
* Introduced `MobileDeviceManager.RevokeDeviceAuth`, which revokes the authentication credential linked to a mobile device.

## v0.4.0

* Added `ById` kind to `RevokeRequest`, which allows revoking a set of credentials by specifying their ID and type.
* Added support for attributes storing a `time.Time` value.
* Updated `IssueToken` and `FindCredential` to return the expiration date.

## v0.3.0

* 💥 **Breaking Change**: `CredentialManager.IssueToken` now returns `token_id` typed as an `int64` rather than `string`.
* **Deprecation**: The `OAuthAccessToken` credential type has been deprecated in favor of `AccessToken`. `NewAccessTokenCredential` should be used instead of `NewOAuthAccessTokenCredential`.
* Introduced `CredentialManager.FindCredential` and `CredentialManager.RevokeCredential`
* Added `IsAuthndToken?` to evaluate the typing of a given token.
* New error result type:
  * `RESULT_FAILED_CREDENTIAL_REVOKED` (23) - indicates that the credential has been revoked.

## v0.2.2

* Added support for the CredentialManager API
* Added support for providing a custom http.RoundTripper

## v0.2.1

* Added support for verbose logging of HTTP responses in the authnd go-client.

## v0.2.0

NOTE: *The server is still compatible with the v0.1.0 client*, this update is not mandatory at this time.

* 💥 **Breaking Change**: In preparation for introducing the new credential management APIs, we renamed several types.
  * Renamed `Request` to `AuthenticateRequest`
  * Renamed `Response` to `AuthenticateResponse`
  * Renamed `NewRequest` to `NewAuthenticateRequest`

## v0.1.0

Initial release
