package types

import (
	"bytes"
	"fmt"

	"github.com/twitchtv/twirp"
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

	name := r.GetName()

	// Check the rules from https://git-scm.com/docs/git-check-ref-format#_description.

	// 1. They can include slash / for hierarchical (directory) grouping,
	// but no slash-separated component can begin with a dot . or end with
	// the sequence .lock.
	for _, part := range bytes.Split(name, []byte("/")) {
		if bytes.HasPrefix(part, []byte(".")) {
			return twirp.InvalidArgumentError("reference.name", "may not have a path component that begins with '.'")
		}
		if bytes.HasSuffix(part, []byte(".lock")) {
			return twirp.InvalidArgumentError("reference.name", "may not have a path component that ends with '.lock'")
		}
	}

	// 2. They must contain at least one /. (verified above)

	// 3. They cannot have two consecutive dots .. anywhere.
	if bytes.Contains(name, []byte("..")) {
		return twirp.InvalidArgumentError("reference.name", "may not include '..'")
	}

	// 4. They cannot have ASCII control characters (i.e. bytes whose
	// values are lower than \040, or \177 DEL), space, tilde ~, caret ^,
	// or colon : anywhere.
	//
	// 5. They cannot have question-mark ?, asterisk *, or open bracket [
	// anywhere.
	for _, b := range name {
		if b < 040 || b == 0177 || b == ' ' || b == '~' || b == '^' || b == ':' || b == '?' || b == '*' || b == '[' {
			return twirp.InvalidArgumentError("reference.name", fmt.Sprintf("may not include 0x%02x", b))
		}
	}

	// 6. They cannot begin or end with a slash / or contain multiple
	// consecutive slashes.
	if bytes.HasPrefix(name, []byte("/")) || bytes.HasSuffix(name, []byte("/")) || bytes.Contains(name, []byte("//")) {
		return twirp.InvalidArgumentError("reference.name", "may not begin or end with a slash or contain multiple consecutive slashes")
	}

	// 7. They cannot end with a dot '.'.
	if bytes.HasSuffix(name, []byte(".")) {
		return twirp.InvalidArgumentError("reference.name", "may not end with a dot")
	}

	// 8. They cannot contain a sequence @{.
	if bytes.Contains(name, []byte("@{")) {
		return twirp.InvalidArgumentError("reference.name", "may not contain '@{'")
	}

	// 9. They cannot be the single character @. (verified above)

	// 10. They cannot contain a \.
	if bytes.Contains(name, []byte("\\")) {
		return twirp.InvalidArgumentError("reference.name", "may not contain a backslash")
	}

	return nil
}
