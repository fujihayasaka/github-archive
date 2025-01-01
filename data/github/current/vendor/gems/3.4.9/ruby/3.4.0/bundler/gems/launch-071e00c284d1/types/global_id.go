package types

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/utils/graphqlid"
)

const (
	GlobalIDInvalidType      = "Invalid"
	GlobalIDUserType         = "User"
	GlobalIDTeamType         = "Team"
	GlobalIDBusinessType     = "Business"
	GlobalIDEnterpriseType   = "Enterprise"
	GlobalIDOrganizationType = "Organization"
	GlobalIDRepositoryType   = "Repository"
	GlobalIDMannequinType    = "Mannequin"
	GlobalIDBotType          = "Bot"
	GlobalIDCheckSuiteType   = "CheckSuite"
)

// GlobalID represents the GlobalID for a Github entity (eg Repository, User)
// IDs are opaque by definition, and should only be resolved to database IDs by github/github
type GlobalID string

// NilGlobalID is an empty GlobalID
var NilGlobalID GlobalID

// Scan implements the Scanner interface.
func (g *GlobalID) Scan(value any) error {
	var s sql.NullString
	err := s.Scan(value)
	if err != nil || !s.Valid {
		*g = NilGlobalID
		return err
	}

	// Use NewGlobalID to log legacy global id uses
	*g = NewGlobalID(context.Background(), s.String)
	return nil
}

func (g GlobalID) IsZeroValue() bool {
	return g == NilGlobalID
}

// IsEquivalent indicates whether the given GlobalID's type and database ID are equivalent to another GlobalID's,
// regardless of their format
func (g GlobalID) IsEquivalent(g2 GlobalID) bool {
	if g == g2 {
		return true
	}
	g1Type, g1ID, err := graphqlid.Decode(g.String())
	if err != nil {
		return false
	}
	g2Type, g2ID, err := graphqlid.Decode(g2.String())
	if err != nil {
		return false
	}
	return g1Type == g2Type && g1ID == g2ID
}

// Value converts the GlobalID to a value suitable for use by the database/sql/driver
func (g GlobalID) Value() (driver.Value, error) {
	return string(g), nil
}

// String returns the string form of the GlobalID.
func (g GlobalID) String() string {
	return string(g)
}

// IsNextGlobalID returns true if the given string is a next global ID
func (g GlobalID) IsNextGlobalID() bool {
	return strings.Contains(g.String(), "_")
}

// CheckFormat() returns an error if the proper global id format isn't being used (next on hosted, legacy on Enterprise)
func (g GlobalID) CheckFormat() error {
	return g.checkFormat(launchconfig.UsingNextGIDs())
}

// ToFeaturesActorID converts the global ID to a string in the form of "Type:ID" that
// the Features API understands.
func (g GlobalID) ToFeaturesActorID() (string, error) {
	typeName, idStr, err := graphqlid.Decode(g.String())
	if err != nil {
		return "", errors.Wrap(err, "error decoding global id")
	}

	if typeName == "Enterprise" {
		typeName = "Business"
	}

	return typeName + ":" + idStr, nil
}

func (g GlobalID) Decode() (string, int64, error) {
	return graphqlid.DecodeTypeIntID(g.String())
}

// conversions

// IdentityToGlobalID converts the Identity to a GlobalID.
// May return NilGlobalID
func IdentityToGlobalID(ctx context.Context, m *pbtypes.Identity) GlobalID {
	return NewGlobalID(ctx, m.GetGlobalId())
}

// IdentityFromGlobalID converts a GlobalID to an identity.
func IdentityFromGlobalID(globalID GlobalID) *pbtypes.Identity {
	return &pbtypes.Identity{
		GlobalId: globalID.String(),
	}
}

// IdentitiesFromGlobalIDs converts a slice of GlobalIDs to identities.
func IdentitiesFromGlobalIDs(globalIDs []GlobalID) []*pbtypes.Identity {
	res := make([]*pbtypes.Identity, 0, len(globalIDs))
	for _, globalID := range globalIDs {
		res = append(res, IdentityFromGlobalID(globalID))
	}
	return res
}

// GlobalIDsFromIdentities converts a slice of Identities to GlobalIds.
func GlobalIDsFromIdentities(ctx context.Context, identities []*pbtypes.Identity) []GlobalID {
	res := make([]GlobalID, 0, len(identities))
	for _, identity := range identities {
		res = append(res, IdentityToGlobalID(ctx, identity))
	}
	return res
}

func (g GlobalID) checkFormat(usingNextFormat bool) error {
	if g.IsZeroValue() {
		return nil
	}

	if usingNextFormat != g.IsNextGlobalID() {
		message := "legacy global id format used. Launch has migrated to the next global id format early, ahead of GitHub as a whole"
		if !usingNextFormat {
			message = "next global id format used on Enterprise. Enterprise isn't migrating to the next global id format"
		}
		return kvperrors.WrapWith(
			errors.New(message),
			kvp.String("global_id", g.String()),
		)
	}

	return nil
}
