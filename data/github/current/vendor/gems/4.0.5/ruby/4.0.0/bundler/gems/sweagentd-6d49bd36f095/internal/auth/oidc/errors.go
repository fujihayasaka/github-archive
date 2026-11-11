package oidc

import "github.com/github/sweagentd/internal/goerrors"

var (
	// ErrTokenExchangeFailed indicates that the RFC 8693 token exchange request failed.
	ErrTokenExchangeFailed = goerrors.New("oidc: token exchange failed")

	// ErrPartialSuccess indicates that some token exchange requests succeeded but others failed.
	ErrPartialSuccess = goerrors.New("oidc: token exchange partially failed")

	// ErrIDPError indicates that the token exchange request failed due to an error from the identity provider.
	ErrIDPError = goerrors.New("oidc: identity provider returned an error during token exchange")

	// ErrUnsupportedGrantType indicates that the token endpoint does not support
	// the requested grant type (e.g. RFC 8693 token exchange).
	ErrUnsupportedGrantType = goerrors.New("oidc: unsupported grant type")

	// ErrInvalidGrant indicates that the token exchange request failed due to an invalid grant (e.g., expired token).
	ErrInvalidGrant = goerrors.New("oidc: invalid grant")

	// ErrTokenRevocationFailed indicates that the token revocation request failed.
	ErrTokenRevocationFailed = goerrors.New("oidc: token revocation failed")

	// ErrPartialRevocationFailed indicates that some tokens failed to revoke.
	ErrPartialRevocationFailed = goerrors.New("oidc: failed to revoke one or more tokens")

	// ErrAuthorizationRequired indicates that the integrator requires the user to
	// complete an authorization flow before tokens can be exchanged.
	ErrAuthorizationRequired = goerrors.New("oidc: user authorization required")

	// ErrUnableToDetermineGrantType indicates that a grant type was not provided and auto discovery failed.
	ErrUnableToDetermineGrantType = goerrors.New("oidc: unable to determine grant type")

	// ErrUnableToDetermineAuthConfig indicates that automated config detection failed
	ErrUnableToDetermineAuthConfig = goerrors.Errorf("oidc: unable to determine authorization config")

	// ErrNetworkError indicates that a network error occurred while attempting to communicate with the identity provider.
	ErrNetworkError = goerrors.New("oidc: network error while communicating with identity provider")

	// ErrInvalidURL indicates that the provided URL is invalid.
	ErrInvalidURL = goerrors.New("oidc: invalid URL")

	// ErrMetadataNotFound indicates that no metadata could be found at the expected discovery endpoints.
	ErrMetadataNotFound = goerrors.New("oidc: metadata not found at discovery endpoint")
)
