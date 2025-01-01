package client

import (
	"sort"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	jwt "github.com/golang-jwt/jwt/v5"
)

type ExchangeTokenDynamicClaims map[string]interface{}

// ExchangeTokenClaims are custom JWT claims which are used to encode identity information
// for an access token exchanged via the TokenExchanger service.
type ExchangeTokenClaims struct {
	jwt.RegisteredClaims

	ActorID   *uint64 `json:"actor.id,omitempty"`
	ActorType *string `json:"actor.type,omitempty"`
	UserLogin *string `json:"user.login,omitempty"`

	CredentialID                 *uint64          `json:"credential.id,omitempty"`
	CredentialType               *string          `json:"credential.type,omitempty"`
	CredentialCreatedAtAttribute *jwt.NumericDate `json:"credential.created_at_utc,omitempty"`
	CredentialScopes             []string         `json:"credential.scopes,omitempty"`
	TokenSuffix                  *string          `json:"token.suffix,omitempty"`

	OrganizationSSOAuthorizedIDs []uint64 `json:"organization.sso_authorized_ids,omitempty"`
	AccessID                     *uint64  `json:"access.id,omitempty"`
	ApplicationID                *uint64  `json:"application.id,omitempty"`
	ApplicationType              *string  `json:"application.type,omitempty"`
	ApplicationClientID          *string  `json:"application.client_id,omitempty"`
	ApplicationOwnerID           *uint64  `json:"application.owner.id,omitempty"`
	ApplicationOwnerType         *string  `json:"application.owner.type,omitempty"`
	InstallationID               *uint64  `json:"installation.id,omitempty"`
	InstallationTargetID         *uint64  `json:"installation.target.id,omitempty"`
	InstallationTargetType       *string  `json:"installation.target.type,omitempty"`
	ScopedInstallationID         *uint64  `json:"scoped_installation.id,omitempty"`
	ScopedInstallationType       *string  `json:"scoped_installation.type,omitempty"`

	// Because FG PATs support 'ExtraAttributes' which can be requested during the IssueToken RPC,
	// we need to support dynamic claims as well in this JWT.  By anonymously imbedding the map
	// here, the default JSON marshaller properly handles inlining DynamicClaims at the root level
	// of the JWT and conversely the UnmarshalJSON method properly handles any claims which are not
	// statically defined in ExchangeTokenClaims into the nested DynamicClaims.
	// ... yay?
	ExchangeTokenDynamicClaims `json:"dynamic_claims,omitempty"`
}

func (c *ExchangeTokenClaims) toProto() []*pb.Attribute {
	potentialAttrs := []*pb.Attribute{
		timeAttribute(CredentialExpiresAtAttribute, c.RegisteredClaims.ExpiresAt),
		timeAttribute(CredentialIssuedAtAttribute, c.RegisteredClaims.IssuedAt),
		integerAttribute(ActorIDAttribute, c.ActorID),
		stringAttribute(ActorTypeAttribute, c.ActorType),
		stringAttribute(UserLoginAttribute, c.UserLogin),
		integerAttribute(CredentialIDAttribute, c.CredentialID),
		stringAttribute(CredentialTypeAttribute, c.CredentialType),
		timeAttribute(CredentialCreatedAtAttribute, c.CredentialCreatedAtAttribute),
		stringListAttribute(CredentialScopesAttribute, c.CredentialScopes),
		stringAttribute(TokenSuffixAttribute, c.TokenSuffix),
		integerListAttribute(OrganizationSSOAuthorizedIdsAttribute, c.OrganizationSSOAuthorizedIDs),
		integerAttribute(ProgrammaticAccessIDAttribute, c.AccessID),
		integerAttribute(ApplicationIDAttribute, c.ApplicationID),
		stringAttribute(ApplicationTypeAttribute, c.ApplicationType),
		stringAttribute(ApplicationClientIDAttribute, c.ApplicationClientID),
		integerAttribute(ApplicationOwnerIDAttribute, c.ApplicationOwnerID),
		stringAttribute(ApplicationOwnerTypeAttribute, c.ApplicationOwnerType),
		integerAttribute(InstallationIDAttribute, c.InstallationID),
		integerAttribute(InstallationTargetIDAttribute, c.InstallationTargetID),
		stringAttribute(InstallationTargetTypeAttribute, c.InstallationTargetType),
		integerAttribute(ScopedInstallationIDAttribute, c.ScopedInstallationID),
		stringAttribute(ScopedInstallationTypeAttribute, c.ScopedInstallationType),
	}

	// ensure we don't include any nil attributes
	attr := make([]*pb.Attribute, 0, len(potentialAttrs))
	for _, pa := range potentialAttrs {
		if pa != nil {
			attr = append(attr, pa)
		}
	}

	// ensure the attributes are sorted consistently so our API is stable
	sort.Slice(attr, func(i, j int) bool {
		return attr[i].Id < attr[j].Id
	})
	return attr
}

type Number interface {
	~int | ~uint64 | ~int64
}

func integerAttribute[N Number](name string, value *N) *pb.Attribute {
	if value == nil {
		return nil
	}

	return pb.NewInt64Attribute(name, int64(*value))
}

func stringAttribute(name string, value *string) *pb.Attribute {
	if value == nil {
		return nil
	}

	return pb.NewStringAttribute(name, *value)
}

func timeAttribute(name string, value *jwt.NumericDate) *pb.Attribute {
	if value == nil {
		return nil
	}

	return pb.NewTimeAttribute(name, value.Time)
}

func stringListAttribute(name string, value []string) *pb.Attribute {
	if value == nil {
		return nil
	}

	return pb.NewStringListAttribute(name, value...)
}

func integerListAttribute[N Number](name string, value []N) *pb.Attribute {
	if value == nil {
		return nil
	}
	vs := make([]int64, 0, len(value))
	for _, v := range value {
		vs = append(vs, int64(v))
	}

	return pb.NewIntegerListAttribute(name, vs...)
}
