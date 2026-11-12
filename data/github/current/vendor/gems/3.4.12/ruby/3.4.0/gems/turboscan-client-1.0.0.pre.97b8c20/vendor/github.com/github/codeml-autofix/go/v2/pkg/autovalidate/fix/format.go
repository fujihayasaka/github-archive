package fix

import (
	"github.com/pkg/errors"
)

// Format indicates on-disk serialization format for a fix entity.
type Format string

const (
	// FormatAutoFixResponse represents the autofix response format.
	FormatAutoFixResponse Format = "autofix-response"
	// FormatFix represents the fix format.
	FormatFix Format = "fix"
)

// String returns the string representation of the fix format.
func (f *Format) String() string {
	return string(*f)
}

// Set parses and assigns the format with validation.
func (f *Format) Set(value string) error {
	switch value {
	case string(FormatAutoFixResponse):
		*f = FormatAutoFixResponse
	case string(FormatFix):
		*f = FormatFix
	default:
		return errors.Errorf("invalid fix format: %s", value)
	}
	return nil
}

// Type returns the type name for Format.
func (f *Format) Type() string {
	return "Format"
}
