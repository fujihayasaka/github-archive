package repofilter

import (
	"fmt"
	"strings"

	"github.com/github/blackbird-mw/internal/types"
)

// F is a filter for selecting repositories from a data store.
type F interface {
	// isFilter is a marker method for structs that implement the
	// RepositoryFilter interface.
	isFilter()

	// Return a serialized represenation of the filter (for debugging).
	String() string
}

// And combines the given filters and requires them all to match.
func And(filters ...F) F {
	return AndFilter{Filters: filters}
}

// Or combines the given filters and requires at least one of them to match.
func Or(filters ...F) F {
	return OrFilter{Filters: filters}
}

// Any matches all repositories.
func Any() F {
	return IsAny{}
}

// Public matches public repositories.
func Public() F {
	return IsPublic{}
}

// Deleted matches deleted repositories.
func Deleted() F {
	return IsDeleted{}
}

func NotDeleted() F {
	return IsNotDeleted{}
}

// NWO matches repositories (hopefully only one!) that have the given NWO.
func NWO(nwo types.NWO) F {
	return NWOFilter{NWO: nwo}
}

// ID matches repositories (hopefully only one!) that have the given ID.
func ID(id types.RepoID) F {
	return IDFilter{ID: id}
}

// IDGreater matches repositories that have an ID greater than the given ID.
func IDGreater(id types.RepoID) F {
	return IDGreaterFilter{ID: id}
}

type IsAny struct{}

func (f IsAny) isFilter() {}

func (f IsAny) String() string {
	return "true"
}

type IsPublic struct{}

func (f IsPublic) isFilter() {}

func (f IsPublic) String() string {
	return "public == true"
}

type IsDeleted struct{}

func (f IsDeleted) isFilter() {}

func (f IsDeleted) String() string {
	return "deleted == true"
}

type IsNotDeleted struct{}

func (f IsNotDeleted) isFilter() {}

func (f IsNotDeleted) String() string {
	return "deleted != true"
}

type NWOFilter struct {
	NWO types.NWO
}

func (f NWOFilter) isFilter() {}

func (f NWOFilter) String() string {
	return fmt.Sprintf("(owner_login == %q AND name == %q)", f.NWO.Owner().String(), f.NWO.Name())
}

type IDFilter struct {
	ID types.RepoID
}

func (f IDFilter) isFilter() {}

func (f IDFilter) String() string {
	return fmt.Sprintf("id == %d", f.ID)
}

type IDGreaterFilter struct {
	ID types.RepoID
}

func (f IDGreaterFilter) isFilter() {}

func (f IDGreaterFilter) String() string {
	return fmt.Sprintf("id > %d", f.ID)
}

type AndFilter struct {
	Filters []F
}

func (f AndFilter) isFilter() {}

func (f AndFilter) String() string {
	components := make([]string, 0, len(f.Filters))
	for _, filter := range f.Filters {
		components = append(components, filter.String())
	}

	return "(" + strings.Join(components, " AND ") + ")"
}

type OrFilter struct {
	Filters []F
}

func (f OrFilter) isFilter() {}

func (f OrFilter) String() string {
	components := make([]string, 0, len(f.Filters))
	for _, filter := range f.Filters {
		components = append(components, filter.String())
	}

	return "(" + strings.Join(components, " OR ") + ")"
}
