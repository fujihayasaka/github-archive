package types

import (
	"strings"

	errs "github.com/pkg/errors"
)

// RepositoryFullName represents the full name (or name with owner, or nwo) of a repository.
type RepositoryFullName struct {
	Owner, Name string
}

var EmptyRepositoryFullName = RepositoryFullName{
	Owner: "",
	Name:  "",
}

// DotRepositoryFullName represents the local repository in the context of reusable workflow
var DotRepositoryFullName = RepositoryFullName{
	Owner: ".",
	Name:  ".",
}

// ParseNWO converts a string like "OWNER/NAME" into a RepositoryFullName{"OWNER","NAME"}.
func ParseNWO(nwo string) (RepositoryFullName, error) {
	if nwo == "." {
		return DotRepositoryFullName, nil
	}

	var res RepositoryFullName
	parts := strings.Split(nwo, "/")
	if len(parts) != 2 {
		return res, errs.Errorf("Invalid RepositoryFullName (%s)", nwo)
	}
	res.Owner = parts[0]
	res.Name = parts[1]
	return res, nil
}

// IsBlank returns true if either part of the name is missing.
func (nwo RepositoryFullName) IsBlank() bool {
	return len(nwo.Owner)+len(nwo.Name) == 0
}

// IsDotRepo returns true if it DotRepositoryFullName
func (nwo RepositoryFullName) IsDotRepo() bool {
	return nwo.Owner == "." && nwo.Name == "."
}

func (nwo RepositoryFullName) IsEqual(other RepositoryFullName) bool {
	return strings.EqualFold(nwo.Owner, other.Owner) && strings.EqualFold(nwo.Name, other.Name)
}

// String returns the string form of the repo's full name.
func (nwo RepositoryFullName) String() string {
	if nwo.IsDotRepo() {
		return "."
	}
	if nwo.IsBlank() {
		return "(unknown)"
	}
	return nwo.Owner + "/" + nwo.Name
}
