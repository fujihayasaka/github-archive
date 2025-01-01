// Package utils provides utility types for use in the autovalidation system.
package utils

import (
	"github.com/pkg/errors"
)

// FixFormat indicates on-disk serialization format for a fix entity.
type FixFormat string

const (
	FixFormatAutoFixResponse FixFormat = "autofix-response"
	FixFormatFix             FixFormat = "fix"
)

// String returns the string representation of the fix format.
func (f *FixFormat) String() string {
	return string(*f)
}

// Set parses and assigns the format with validation.
func (f *FixFormat) Set(value string) error {
	switch value {
	case string(FixFormatAutoFixResponse):
		*f = FixFormatAutoFixResponse
	case string(FixFormatFix):
		*f = FixFormatFix
	default:
		return errors.Errorf("invalid fix format: %s", value)
	}
	return nil
}

// Type returns the type name for FixFormat.
func (f *FixFormat) Type() string {
	return "FixFormat"
}
