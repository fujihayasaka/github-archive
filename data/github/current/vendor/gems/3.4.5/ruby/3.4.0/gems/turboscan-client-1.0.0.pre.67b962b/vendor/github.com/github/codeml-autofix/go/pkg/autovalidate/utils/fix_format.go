package utils

import "fmt"

type FixFormat string

const (
	FixFormatAutoFixResponse FixFormat = "autofix-response"
	FixFormatFix             FixFormat = "fix"
)

func (f *FixFormat) String() string {
	return string(*f)
}
func (f *FixFormat) Set(value string) error {
	switch value {
	case string(FixFormatAutoFixResponse):
		*f = FixFormatAutoFixResponse
	case string(FixFormatFix):
		*f = FixFormatFix
	default:
		return fmt.Errorf("invalid fix format: %s", value)
	}
	return nil
}
func (f *FixFormat) Type() string {
	return "FixFormat"
}
