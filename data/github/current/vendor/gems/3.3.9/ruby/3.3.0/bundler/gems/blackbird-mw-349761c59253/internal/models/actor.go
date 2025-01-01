package models

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/gob"
	"fmt"
	"sort"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/types"
)

// Actor is a GitHub user issuing a search in blackbird along with enough
// information about that user to make access control decisions. The IP is important for
// Conditional Access Policy decisions where Orgs can limit access to certain IP addresses.
type Actor struct {
	ID                        uint32
	IP                        string
	AccessiblePrivateRepoIDs  types.RepoIDSet
	AccessibleOrganizationIDs types.U32Set
	AuthorizedOrganizationIDs []int64
	ProtectedOrganizationIDs  []int64
	CacheExpiryTime           int64  // The expiry time of the cache, in seconds since epoch
	SessionID                 string // A string that uniquely identifies the user's session

	ownerSuggestions []*Owner   // cache of owner suggestions (not serialized)
	tenant           *pb.Tenant // optional tenant (not serialized)
}

func NewAnonymousActor() *Actor {
	return &Actor{
		ID:                        0,
		AccessiblePrivateRepoIDs:  types.RepoIDSet{},
		AccessibleOrganizationIDs: types.U32Set{},
		AuthorizedOrganizationIDs: []int64{},
		ProtectedOrganizationIDs:  []int64{},
	}
}

// Set the tenant for an actor
func (a *Actor) SetTenant(tenant *pb.Tenant) {
	if a != nil {
		a.tenant = tenant
	}
}

// Get the tenant for an actor
func (a *Actor) GetTenant() *pb.Tenant {
	if a != nil {
		return a.tenant
	}
	return nil
}

// Is this actor a member of the GitHub organization on github.com?
func (a *Actor) IsGitHubStaff() bool {
	if a.GetTenant() != nil {
		// No such thing on proxima (multi-tenant github).
		return false
	}

	for _, id := range a.AuthorizedOrganizationIDs {
		if id == constants.GitHubOrgID {
			return true
		}
	}
	return false
}

// Fetch and cache a list of owners for this actor.
func (a *Actor) FetchOwnerSuggetions(fetch func(ids []int64) ([]*Owner, error)) ([]*Owner, error) {
	if a.ownerSuggestions == nil {
		var err error
		ids := a.AuthorizedOrganizationIDs
		ids = append(ids, int64(a.ID))
		owners, err := fetch(ids)
		if err != nil {
			return nil, err
		}
		a.ownerSuggestions = owners
	}
	return a.ownerSuggestions, nil
}

func (a Actor) Marshal() ([]byte, error) {
	var buf bytes.Buffer
	err := gob.NewEncoder(&buf).Encode(a)
	return buf.Bytes(), err
}

func (a *Actor) Unmarshal(data []byte) error {
	return gob.NewDecoder(bytes.NewReader(data)).Decode(a)
}

// Equality function for two actors to verify potential differences between V1 and V2 actors.
// It is not intended to be used as a deep equality check.
func (a *Actor) Equal(ctx context.Context, other *Actor) bool {
	if a == nil {
		logging.Info(ctx, "actor mismatch", kvp.String("field", "actor"), kvp.String("expected", "not nil"), kvp.String("actual", "nil"))
		return false
	}

	if other == nil {
		logging.Info(ctx, "actor mismatch", kvp.String("field", "other actor"), kvp.String("expected", "nil"), kvp.String("actual", "not nil"))
		return false
	}

	if a.ID != other.ID {
		logging.Info(ctx, "actor mismatch", kvp.String("field", "id"), kvp.Int64("expected", int64(a.ID)), kvp.Int64("actual", int64(other.ID)))
		return false
	}

	if a.IP != other.IP {
		logging.Info(ctx, "actor mismatch", kvp.String("field", "ip"), kvp.String("expected", a.IP), kvp.String("actual", other.IP))
		return false
	}

	if a.SessionID != other.SessionID {
		logging.Info(ctx, "actor mismatch", kvp.String("field", "session id"), kvp.String("expected", a.SessionID), kvp.String("actual", other.SessionID))
		return false
	}

	if len(a.AccessiblePrivateRepoIDs) != len(other.AccessiblePrivateRepoIDs) {
		logging.Info(ctx, "actor mismatch", kvp.String("field", "accessible private repo ids"), kvp.Int("expected", len(a.AccessiblePrivateRepoIDs)), kvp.Int("actual", len(other.AccessiblePrivateRepoIDs)))
		return false
	}

	if len(a.AccessibleOrganizationIDs) != len(other.AccessibleOrganizationIDs) {
		logging.Info(ctx, "actor mismatch", kvp.String("field", "accessible organization ids"), kvp.Int("expected", len(a.AccessibleOrganizationIDs)), kvp.Int("actual", len(other.AccessibleOrganizationIDs)))
		return false
	}

	if len(a.AuthorizedOrganizationIDs) != len(other.AuthorizedOrganizationIDs) {
		logging.Info(ctx, "actor mismatch", kvp.String("field", "authorized organization ids"), kvp.Int("expected", len(a.AuthorizedOrganizationIDs)), kvp.Int("actual", len(other.AuthorizedOrganizationIDs)))
		return false
	}

	if len(a.ProtectedOrganizationIDs) != len(other.ProtectedOrganizationIDs) {
		logging.Info(ctx, "actor mismatch", kvp.String("field", "protected organization ids"), kvp.Int("expected", len(a.ProtectedOrganizationIDs)), kvp.Int("actual", len(other.ProtectedOrganizationIDs)))
		return false
	}

	return true
}

func (a *Actor) AccessibleRepoIDKeys() []types.RepoID {
	ids := make([]types.RepoID, 0, len(a.AccessiblePrivateRepoIDs))
	for id := range a.AccessiblePrivateRepoIDs {
		ids = append(ids, types.RepoID(id))
	}
	return ids
}

func (a *Actor) Hash() string {
	h := sha256.New()

	// Write the ID
	_ = binary.Write(h, binary.LittleEndian, a.ID)

	// Write the IP
	h.Write([]byte(a.IP))

	// Hash the repo IDs
	ids := make([]uint64, len(a.AccessiblePrivateRepoIDs))
	for k := range a.AccessiblePrivateRepoIDs {
		ids = append(ids, uint64(k))
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	_ = binary.Write(h, binary.LittleEndian, ids)

	// Hash the accessible organizations
	ids = make([]uint64, len(a.AccessibleOrganizationIDs))
	for k := range a.AccessibleOrganizationIDs {
		ids = append(ids, uint64(k))
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	_ = binary.Write(h, binary.LittleEndian, ids)

	// Hash the protected organizations
	ids = make([]uint64, len(a.ProtectedOrganizationIDs))
	for k := range a.ProtectedOrganizationIDs {
		ids = append(ids, uint64(k))
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	_ = binary.Write(h, binary.LittleEndian, ids)

	// Hash the session ID
	h.Write([]byte(a.SessionID))

	return fmt.Sprintf("%x", h.Sum(nil))
}
