package types

import (
	"fmt"
	"strings"

	"github.com/pkg/errors"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

type NWO struct {
	owner Owner
	name  string
}

// Create a NWO from a string in the form "<owner>/<name>".
// Returns an error if nwo is invalid.
func NewNWO(nwo string) (NWO, error) {
	parts := strings.Split(nwo, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return NWO{}, errors.Errorf("%q is not a valid repo nwo", nwo)
	}

	owner, err := NewOwner(parts[0])
	if err != nil {
		return NWO{}, err
	}

	return NWO{owner: owner, name: parts[1]}, nil
}

// Create a NWO from a string in the form "<owner>/<name>".
// Panics if nwo is invalid.
func NWOFromString(nwo string) NWO {
	n, err := NewNWO(nwo)
	if err != nil {
		panic(err)
	}
	return n
}

func IsValidRepoNWO(nwo string) bool {
	_, err := NewNWO(nwo)
	return err == nil
}

// Returns the unique owner name (includes tenant shortcode suffix if there is one)
func (n NWO) Owner() Owner {
	return n.owner
}

// Return the name of the repo
func (n NWO) Name() string {
	return n.name
}

// Returns the display nwo (no tenant shortcode suffix on the owner)
func (n NWO) NameWithDisplayOwner(tenant *pb.Tenant) string {
	return fmt.Sprintf("%s/%s", n.owner.DisplayLogin(tenant), n.name)
}

// Returns the unique nwo string (includes tenant shortcode suffix on the owner if there is one)
func (n NWO) NameWithUniqueOwner(tenant *pb.Tenant) string {
	return fmt.Sprintf("%s/%s", n.owner.UniqueLogin(tenant), n.name)
}

// Returns the unique nwo string (includes tenant shortcode suffix if there is one)
func (n NWO) String() string {
	if n.owner.String() == "" && n.name == "" {
		return ""
	}

	return fmt.Sprintf("%s/%s", n.owner, n.name)
}

func (n NWO) Equal(other NWO) bool {
	return strings.EqualFold(n.String(), other.String())
}
