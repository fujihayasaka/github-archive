package types

import (
	"bytes"

	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/internal/validators"
)

// headReferenceName is the symbolic ref "HEAD". Git uses this to track the tip
// of the current branch. In a bare repository, it points to the tip of the
// default branch, and is the source of truth about that.
const headReferenceName = "HEAD"

func NewReference(name []byte) *Reference {
	return &Reference{Name: name}
}

// DefaultBranch is a helper for constructing a Reference that points to the tip
// of the default branch.
func DefaultBranch() *Reference {
	return NewReference([]byte(headReferenceName))
}

func (r *Reference) IsDefaultBranch() bool {
	return bytes.Equal(r.GetName(), []byte(headReferenceName))
}

func (r *Reference) Validate() error {
	if r == nil {
		return nil
	}

	name := r.GetName()

	if len(name) == 0 {
		return twirp.RequiredArgumentError("reference.name")
	}

	if bytes.Equal(name, []byte(headReferenceName)) {
		return nil
	}

	if !bytes.HasPrefix(name, []byte("refs/")) {
		return twirp.InvalidArgumentError("reference.name", "must have a 'refs/' prefix or be HEAD")
	}

	return nil
}

func (r *Reference) ValidateFormat() error {
	if err := r.Validate(); err != nil {
		return err
	}

	return validators.ReferenceName(r.GetName(), "reference.name")
}
