# Authnd Ruby Client Changelog

**NOTE:** This is manually maintained and shouldn't be considered a perfectly authoritative source for changes

## v0.23.1

* Fixes critical bugs in the `Authnd::Client::StatelessTokenVerifier` added in v0.22.0
  * Ensures `exp`, `iat`, `nbf`, and `iss` claims are verified
  * Ensure signature validation is performed properly

## v0.23.0

* Upgrade to Ruby v3.4.1

## v0.22.3

* Update response from find_active_device_auth to include `has_expired_auth_request` boolean value.

## v0.22.2

* [Bugfix] addresses a bug where exchange token attributes specific to GitHub and OAuth App tokens were missing

## v0.22.1

* Added new TokenExchange method to exchange public access tokens for authnd-issued Exchange Tokens (JWTs)

## v0.22.0

* Added new StatelessTokenVerifier method to verify Exchange Tokens (JWTs)

## v0.20.1

* Added new RESULT_FAILED_APPLICATION_OWNER_SPAMMY result type

## v0.20.0

* Locks the google-protobuf and libprotoc versions and regenerates the Ruby proto files for compatibility with github/github. (#2471)

## v0.19.0

* Unlocks the `faraday` gem.  Previously, it was pinned to the v0.17.x minor version. (#2398)

## v0.18.1

* Updates the `TenantContext` faraday middleware to support the tenant slug (`X-GitHub-Tenant`) for RPCs to authnd in Proxima.
  * Tenant headers are required in Proxima and ignored in GHES/GHEC/Dotcom.
  * Tenant headers are ignored in GHES/GHEC/Dotcom.

## v0.18.0

* Adds a `TenantContext` faraday middleware to support adding tenancy ID (`X-GitHub-Tenant-ID`) and shortcode (`X-GitHub-Tenant-Shortcode`) for RPCs to authnd in Proxima.
  * Tenant headers are required in Proxima and ignored in GHES/GHEC/Dotcom.

## v0.17.0

* Adds two new ways to revoke mobile device keys (`revoke_device_keys_by_oauth_access_ids` and `revoke_device_keys_by_ids`).

## v0.16.0

* Updates proto definitions and updates `request_device_auth` to accept optional `device_ip` and `device_name` args.
* Updates response from find_active_device_auth to include `created_at_utc`, `ip_address` (if it exists), and `device_display_name` (if it exists).

## v0.15.0

* Adds the `Authnd::Client::CredentialManager.issue_signed_auth_token` method with support for issuing user- and session-scoped tokens.
  * Known limitations with attributes:
    * Only flat hashes with string keys are supported.
    * Time objects are not supported as values.

## v0.14.5

* Added `access_id` and `expires_at` to the verify credentials response.

## v0.14.4

* Added `format_features_for_header` method which encodes an `Array` of features for usage with the `X-GitHub-Features` header.  Any features provided in that header will be interpreted by `authnd` for gating server-side behavior.  Example usage:

```
features = []
features << "notifyd_beta_sender" if GitHub.flipper[:notifyd_beta_sender].enabled?
Authnd::Client.authenticator_for("github/apps").authenticate(request, headers: {
  Authnd::Client::FEATURES_HEADER: Authnd::Client.format_features_for_header(features),
})
```

## v0.14.3

* Added constants for well-known response attributes: `actor.type`, `application.type`, and `credential.type`.

## v0.14.2

* `Authnd::Client::MobileDeviceManager.find_device_auth_key_registrations`, now returns `OauthAccessId` with the response.

## v0.14.1

* Updates `Authnd::Client::CredentialManager.verify_credentials` to return a `result` which will containing success or a failure reason.

## v0.14.0

* Introduced `Authnd::Client::MobileDeviceManager.revoke_device_keys_by_user_id`. This function can be used to revoke all device keys by a user ID.

## v0.13.1

* `Authnd::Client::MobileDeviceManager.request_device_auth` supports `2fa_password_reset` as a `type`.

## v0.13.0

* `Authnd::Client::Authenticator.authenticate` now validates requests before sending to authnd, throwing if a requests's credentials are egregiously invalid

## v0.12.1

* `Authnd::Client::MobileDeviceManager.find_active_device_auth`, now returns a `type` with the response.

## v0.12.0

* Added `type` as an input to `Authnd::Client::MobileDeviceManager.request_device_auth`.
  * Default value is `2fa_login`.
  * Supported values are: `['2fa_login', 'device_verification']`.

## v0.11.6

* `Authnd::Client::MobileDeviceManager.register_device_key` now allows `nil` or empty string for `device_name` and `device_model` args.

## v0.11.5

* Allow kwargs in class/args middleware instantiation and prevent same middleware instance from being applied twice.

## v0.11.4

* Small adjustment to timing middleware to support emitting time (with error) in the case of a raise from inner perform(s).

## v0.11.3

* Adds timing middleware, and improves decorator for applying middleware to the client.

## v0.11.2

* Adds already approved and already rejected result enums to the `approve_device_auth` and `rejected_device_auth` responses.

## v0.11.1

* Removing support for prototype `V0Token` token previously issued by Authnd.
* CredentialManager and Authentication APIs no longer accept V0 tokens.
* V0 tokens are no longer recognized by `authnd_token?` helper method.

## v0.11.0

* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.reject_device_auth` no longer accepts a signature or signature version.

## v0.10.0

* Added `Authnd::CredentialManagerService.verify_credentials` for verifying tokens issued by Authnd.  Currently only programmatic acces tokens are supported. This does not constitute authentication. Its primary purpose is gather a limited set of attributes associated with the token during secret scanning.
* Updates `AUTHND_TOKEN_REGEX` to match the new `github_pat_1` token prefix for programmatic access tokens ([ADR](https://github.com/github/authnd/pull/1335)).
* Refactors client services to support per-method retry enablement.

## v0.9.6

* Updates `authnd_token?` to check the token against a regexp pattern which matches all authnd-issued tokens.  Previously, this function just did prefix matching.

## v0.9.5

* Introduced optional `skip_challenge` kwarg to `Authnd::Client::MobileDeviceManager.request_device_auth`. This can be used to skip the challenge prompt for mobile device auth approval.
* Introduced `challenge_required` on response from `Authnd::Client::MobileDeviceManager.find_active_device_auth`. This can be used to determine if the challenge needs to be used when signing the payload for mobile device auth approval.

## v0.9.4

* Introduced `Authnd::Client::MobileDeviceManager.find_device_auth_key_registration`. This function can be used to evaluate if a `user_id` and `oauth_access_id` are associated with a registered device auth key.

## v0.9.3

* `Authnd::Client::Authenticator.authenticate` now returns the token's configured expires at time for programmatic access tokens.
* `Authnd::Client::Authenticator.authenticate` now returns the `user.login` attribute for signed auth tokens.
* `Authnd::Client::MobileDeviceManager.register_device_key` now revokes all active device auth keys associated with the provided OAuth Access ID before registering the provided key.
* `Authnd::Client::MobileDeviceManager.revoke_device_auth_key_by_oauth_access_id` now revokes all active device auth keys associated with the provided OAuth Access ID.

## v0.9.2

* `Authnd::Client::MobileDeviceManager.find_device_auth_key_registrations`, now returns `created_at_time` & `expires_at_time` with the response.

## v0.9.1

* `Authnd::Client::MobileDeviceManager.request_device_auth`, now returns an `expires_at_time` with the response.

## v0.9.0

* Introduced `Authnd::Client::MobileDeviceManager.register_device_key`. This function can be used to register a device auth key _or_ a device recovery key.
* Introduced `Authnd::Client::MobileDeviceManager.revoke_device_auth_key_by_oauth_access_id`. This function can be used to revoke a device auth key by oauth access ID.
* Introduced `Authnd::Client::MobileDeviceManager.find_device_auth_key_registrations`, which fetches all device auth key registrations associated with a user.
* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.get_device_auth_status` now requires user_id as a second argument.
* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.find_active_device_auth` now requires oauth_access_id as a second argument.
* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.approve_device_auth` now requires oauth_access_id as an argument instead of device_id.
* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.reject_device_auth` now requires oauth_access_id as an argument instead of device_id.
* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.register_device` was removed in favor or `register_device_key`.
* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.revoke_device_auth` was removed in favor or `revoke_device_auth_key_by_oauth_access_id`.
* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.update_device` was removed.

## v0.8.0

* Introduced `Authnd::Client::MobileDeviceManager.approve_device_auth`, which approves a device auth request.
* Introduced `Authnd::Client::MobileDeviceManager.reject_device_auth`, which rejects a device auth request.

## v0.7.0

* BREAKING CHANGE: Added request argument `user_id` to `Authnd::Client::MobileDeviceManager.update_device`, which updates attributes associated with a mobile device.
* BREAKING CHANGE: Added request argument `user_id` to `Authnd::Client::MobileDeviceManager.revoke_device`, which revokes the authentication credential linked to a mobile device.

## v0.6.0

* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.register_device` arguments have changed. Now requires arguments used to validate the provided public keys.
* BREAKING CHANGE: `Authnd::Client::MobileDeviceManager.update_device` arguments have changed. Now requires arguments used to validate the provided public key.
* Introduced `Authnd::Client::MobileDeviceManager.request_device_auth` to initiate a mobile device authentication attempt.
* Introduced `Authnd::Client::MobileDeviceManager.get_device_auth_status` to retrieve the status of a device auth request.
* Introduced `Authnd::Client::MobileDeviceManager.find_active_device_auth` to find an active device auth request for a given user.

## v0.5.0

* BREAKING CHANGE: Removed deprecated `OAuthAccessToken`(`Authnd::Proto::Credentials.oauth_access_token`) credential type.
* Introduced `Authnd::Client::MobileDeviceManager.register_device`, which registers a mobile device associated with a user.
* Introduced `Authnd::Client::MobileDeviceManager.update_device`, which updates attributes associated with a mobile device.
* Introduced `Authnd::Client::MobileDeviceManager.revoke_device_auth`, which revokes the authentication credential linked to a mobile device.

## v0.4.0

* BREAKING CHANGE: `Authnd::Client::CredentialManager.revoke_credentials` now expects an Array of `Authnd::Proto::Credentials` instead of a Hash.
* Added `Authnd::Client::CredentialManager.revoke_credentials_by_id`, which allows revoking a set of credentials by specifying their ID.
* Updated `IssueToken` and `FindCredential` to return the expiration date.
* Added support for attributes storing a `Time` value.

## v0.3.0

* BREAKING CHANGE: `Authnd::Client::CredentialManager.issue_token` now returns `token_id` typed as an `int` rather than `string`.
* DEPRECATION: The `OAuthAccessToken` credential type has been deprecated in favor of `AccessToken`. `Authnd::Proto::Credentials.access_token` should be used instead of `Authnd::Proto::Credentials.oauth_access_token`.
* Introduced `Authnd::Client::CredentialManager.find_credential` and `Authnd::Client::CredentialManager.revoke_credential`
* Added `Authnd::Client::authnd_token?` to evaluate the typing of a given token.
* New error result type:
  * `RESULT_FAILED_CREDENTIAL_REVOKED` (23) - indicates that the credential has been revoked.

## v0.1.1

* BREAKING CHANGE: `Authnd::Proto::Error.new` now takes keyword arguments instead of positional for `message` and `twirp_error`
* Make twirp error data in `Authnd::Proto::Error` more visible

## v0.1.0

NOTE: **This version is retro-versioned from a prior v2 release that was never used except as vendored-in to dotcom**

* BREAKING CHANGE: `Authnd::Proto::AuthenticateRequest` no longer has a `source_ip` field or constructor argument.
* BREAKING CHANGE: `Authnd::Client::Authenticator` now requires the `catalog_service` keyword argument.
* BREAKING CHANGE: `Authnd::Client` is now `Authnd::Client::Authenticator`.
* BREAKING CHANGE: `Authnd::Client::Authenticator` no longer accepts a string for connection. Must be a `Faraday::Connection`.
* Introduced "decoratable" client and Authnd::Client::Middleware.
* Added retry middleware and option for request hedging.
* New error result types:
  * RESULT_FAILED_CREDENTIAL_EXPIRED (17) - indicates that the credential (Oauth token, etc.) has expired.
  * RESULT_FAILED_NOT_SUPPORTED (18) - indicates that the requested operation is not supported.
* Removed support for SSH Fingerprint Authentication (which hasn't ever been supported in the server in production).
* Include richer metadata about twirp errors when raising `Authnd::Proto::Error`
