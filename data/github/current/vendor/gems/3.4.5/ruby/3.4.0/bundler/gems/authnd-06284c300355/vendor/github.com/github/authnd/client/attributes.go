package client

// well known attribute ids used in authn requests and/or responses
const (
	// universal attributes for actors
	ActorIDAttribute   = "actor.id"
	ActorTypeAttribute = "actor.type"
	UserLoginAttribute = "user.login"

	// universal attributes for credentials
	CredentialIDAttribute        = "credential.id"
	CredentialPayloadAttribute   = "credential.payload"
	CredentialScopesAttribute    = "credential.scopes"
	CredentialTypeAttribute      = "credential.type"
	CredentialVersionAttribute   = "credential.version"
	CredentialCreatedAtAttribute = "credential.created_at_utc"
	CredentialExpiresAtAttribute = "credential.expires_at_utc"
	CredentialIssuedAtAttribute  = "credential.issued_at_utc"
	TokenSuffixAttribute         = "token.suffix"

	// oauth specific attributes
	ProgrammaticAccessIDAttribute         = "access.id"
	OrganizationSSOAuthorizedIdsAttribute = "organization.sso_authorized_ids"

	// public key specific attributes
	PublicKeyNotVerifiedAttribute = "publickey.notverified"

	// SAT specific attributes
	SessionIDAttribute = "session.id"

	// oauth app/u2s specific attributes
	ApplicationIDAttribute        = "application.id"
	ApplicationTypeAttribute      = "application.type"
	ApplicationClientIDAttribute  = "application.client_id"
	ApplicationOwnerIDAttribute   = "application.owner.id"
	ApplicationOwnerTypeAttribute = "application.owner.type"

	// github app specific attributes
	InstallationIDAttribute         = "installation.id"
	InstallationTargetIDAttribute   = "installation.target.id"
	InstallationTargetTypeAttribute = "installation.target.type"
	ScopedInstallationTypeAttribute = "scoped_installation.type"
	ScopedInstallationIDAttribute   = "scoped_installation.id"
)

// should contain a registry of all known attributes so that our stateless token
// implementation can account for them in the statically defined JWT claims
var AllAttributes = []string{
	ProgrammaticAccessIDAttribute,
	ActorIDAttribute,
	ActorTypeAttribute,
	ApplicationIDAttribute,
	ApplicationTypeAttribute,
	ApplicationClientIDAttribute,
	ApplicationOwnerIDAttribute,
	ApplicationOwnerTypeAttribute,
	CredentialCreatedAtAttribute,
	CredentialExpiresAtAttribute,
	CredentialIDAttribute,
	CredentialIssuedAtAttribute,
	CredentialPayloadAttribute,
	CredentialScopesAttribute,
	CredentialTypeAttribute,
	CredentialVersionAttribute,
	InstallationIDAttribute,
	InstallationTargetIDAttribute,
	InstallationTargetTypeAttribute,
	OrganizationSSOAuthorizedIdsAttribute,
	PublicKeyNotVerifiedAttribute,
	ScopedInstallationIDAttribute,
	ScopedInstallationTypeAttribute,
	SessionIDAttribute,
	TokenSuffixAttribute,
	UserLoginAttribute,
}
