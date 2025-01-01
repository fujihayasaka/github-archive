package client

import (
	"sort"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	jwt "github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
)

func TestTokenClaims_toProto(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)

	claims := &ExchangeTokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(1 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(now.Add(-1 * time.Hour)),
		},
		ActorID:                      intPtr(1),
		CredentialID:                 intPtr(2),
		AccessID:                     intPtr(3),
		ApplicationID:                intPtr(4),
		InstallationID:               intPtr(5),
		InstallationTargetID:         intPtr(6),
		InstallationTargetType:       strPtr("installation-target-type"),
		ScopedInstallationID:         intPtr(7),
		ActorType:                    strPtr("actor-type"),
		UserLogin:                    strPtr("user-login"),
		CredentialType:               strPtr("credential-type"),
		TokenSuffix:                  strPtr("token-suffix"),
		ApplicationType:              strPtr("application-type"),
		ApplicationClientID:          strPtr("client-id"),
		ApplicationOwnerID:           intPtr(8),
		ApplicationOwnerType:         strPtr("application-owner-type"),
		ScopedInstallationType:       strPtr("scoped-installation-type"),
		CredentialScopes:             []string{"scope1", "scope2"},
		CredentialCreatedAtAttribute: jwt.NewNumericDate(now),
		OrganizationSSOAuthorizedIDs: []uint64{98, 99},
	}

	expected := []*pb.Attribute{
		pb.NewTimeAttribute(CredentialExpiresAtAttribute, now.Add(1*time.Hour)),
		pb.NewTimeAttribute(CredentialIssuedAtAttribute, now.Add(-1*time.Hour)),
		pb.NewInt64Attribute(ActorIDAttribute, 1),
		pb.NewInt64Attribute(CredentialIDAttribute, 2),
		pb.NewInt64Attribute(ProgrammaticAccessIDAttribute, 3),
		pb.NewInt64Attribute(ApplicationIDAttribute, 4),
		pb.NewInt64Attribute(InstallationIDAttribute, 5),
		pb.NewInt64Attribute(InstallationTargetIDAttribute, 6),
		pb.NewStringAttribute(InstallationTargetTypeAttribute, "installation-target-type"),
		pb.NewInt64Attribute(ScopedInstallationIDAttribute, 7),
		pb.NewInt64Attribute(ApplicationOwnerIDAttribute, 8),
		pb.NewStringAttribute(ApplicationOwnerTypeAttribute, "application-owner-type"),
		pb.NewStringAttribute(ActorTypeAttribute, "actor-type"),
		pb.NewStringAttribute(UserLoginAttribute, "user-login"),
		pb.NewStringAttribute(CredentialTypeAttribute, "credential-type"),
		pb.NewStringAttribute(TokenSuffixAttribute, "token-suffix"),
		pb.NewStringAttribute(ApplicationTypeAttribute, "application-type"),
		pb.NewStringAttribute(ApplicationClientIDAttribute, "client-id"),
		pb.NewStringAttribute(ScopedInstallationTypeAttribute, "scoped-installation-type"),
		pb.NewStringListAttribute(CredentialScopesAttribute, "scope1", "scope2"),
		pb.NewTimeAttribute(CredentialCreatedAtAttribute, now),
		pb.NewIntegerListAttribute(OrganizationSSOAuthorizedIdsAttribute, 98, 99),
	}
	sort.Slice(expected, func(i, j int) bool {
		return expected[i].Id < expected[j].Id
	})

	assert.Equal(t, expected, claims.toProto())
}

func intPtr(i uint64) *uint64 {
	return &i
}

func strPtr(s string) *string {
	return &s
}
