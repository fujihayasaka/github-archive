// Package validate provides validation functions for git commits and refs.
package validate

import (
	"regexp"
)

var (
	commitOid    *regexp.Regexp = regexp.MustCompile(`^[0-9a-f]{40}$`)
	qualifiedRef *regexp.Regexp = regexp.MustCompile(`^refs/(heads|pull|tags)/.*$`)
)

// IsCommitOid returns true if (and only if) the string is a valid SHA
func IsCommitOid(s string) bool {
	return commitOid.MatchString(s)
}

// IsRef returns true if (and only if) the string is a fully qualified ref
func IsRef(ref []byte) bool {
	return qualifiedRef.Match(ref)
}
