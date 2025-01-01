// Package utils contains various utility functions
package utils

import "strings"

// NormalizeEmail normalizes an email address by converting it to lowercase
// and trimming whitespace.
func NormalizeEmail(s string) string {
	return strings.TrimSpace(strings.ToLower(s))
}
