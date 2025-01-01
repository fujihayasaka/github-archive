package validators

import (
	"bytes"
	"fmt"

	"github.com/twitchtv/twirp"
)

func ReferenceName(name []byte, field string) error {
	// Check the rules from https://git-scm.com/docs/git-check-ref-format#_description.

	// 1. They can include slash / for hierarchical (directory) grouping,
	// but no slash-separated component can begin with a dot . or end with
	// the sequence .lock.
	for _, part := range bytes.Split(name, []byte("/")) {
		if bytes.HasPrefix(part, []byte(".")) {
			return twirp.InvalidArgumentError(field, "may not have a path component that begins with '.'")
		}
		if bytes.HasSuffix(part, []byte(".lock")) {
			return twirp.InvalidArgumentError(field, "may not have a path component that ends with '.lock'")
		}
	}

	// 2. They must contain at least one /. (verified elsewhere)

	// 3. They cannot have two consecutive dots .. anywhere.
	if bytes.Contains(name, []byte("..")) {
		return twirp.InvalidArgumentError(field, "may not include '..'")
	}

	// 4. They cannot have ASCII control characters (i.e. bytes whose
	// values are lower than \040, or \177 DEL), space, tilde ~, caret ^,
	// or colon : anywhere.
	//
	// 5. They cannot have question-mark ?, asterisk *, or open bracket [
	// anywhere.
	for _, b := range name {
		if b < 040 || b == 0177 || b == ' ' || b == '~' || b == '^' || b == ':' || b == '?' || b == '*' || b == '[' {
			return twirp.InvalidArgumentError(field, fmt.Sprintf("may not include 0x%02x", b))
		}
	}

	// 6. They cannot begin or end with a slash / or contain multiple
	// consecutive slashes.
	if bytes.HasPrefix(name, []byte("/")) || bytes.HasSuffix(name, []byte("/")) || bytes.Contains(name, []byte("//")) {
		return twirp.InvalidArgumentError(field, "may not begin or end with a slash or contain multiple consecutive slashes")
	}

	// 7. They cannot end with a dot '.'.
	if bytes.HasSuffix(name, []byte(".")) {
		return twirp.InvalidArgumentError(field, "may not end with a dot")
	}

	// 8. They cannot contain a sequence @{.
	if bytes.Contains(name, []byte("@{")) {
		return twirp.InvalidArgumentError(field, "may not contain '@{'")
	}

	// 9. They cannot be the single character @. (verified above)

	// 10. They cannot contain a \.
	if bytes.Contains(name, []byte("\\")) {
		return twirp.InvalidArgumentError(field, "may not contain a backslash")
	}

	return nil
}
