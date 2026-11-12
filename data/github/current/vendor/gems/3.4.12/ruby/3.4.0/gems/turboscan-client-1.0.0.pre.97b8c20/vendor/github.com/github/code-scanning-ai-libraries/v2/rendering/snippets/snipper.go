// Package snippets provides utilities for extracting code snippets and handling line numbers.
package snippets

import (
	"regexp"
)

// InitialLineNumberRegex matches a line number at the start of a line.
var InitialLineNumberRegex = regexp.MustCompile(`^[\d.]+: ?`)

// LineNumberRegex matches line numbers using InitialLineNumberRegex in multiline mode.
var LineNumberRegex = regexp.MustCompile(`(?m)` + InitialLineNumberRegex.String())
