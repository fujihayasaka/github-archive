// Package output provides types and utilities for handling different output formats.
package output

import (
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/sarif"
	"github.com/go-errors/errors"
)

// Format represents the output format type.
type Format string

// Supported output formats.
const (
	FormatAutofixFeedback Format = "autofix-feedback"
	FormatSarif           Format = "sarif"
)

// String returns the string representation of the format.
func (f *Format) String() string {
	return string(*f)
}

// Set sets the format from a string value.
func (f *Format) Set(value string) error {
	switch value {
	case string(FormatAutofixFeedback):
		*f = FormatAutofixFeedback
	case string(FormatSarif):
		*f = FormatSarif
	default:
		return errors.Errorf("invalid output format: %s", value)
	}
	return nil
}

// Type returns the type name for the flag.
func (f *Format) Type() string {
	return "Format"
}

// AutofixFeedbackOutput represents the response from the autovalidate process.
type AutofixFeedbackOutput struct {
	Validator string `json:"validator"`
	Reason    string `json:"reason"`
	Verdict   bool   `json:"verdict"`
}

// IsResult implements the validators.Result interface for AutofixFeedbackOutput.
func (*AutofixFeedbackOutput) IsResult() {}

// SarifOutput represents a validator result in SARIF format.
type SarifOutput struct {
	Log sarif.Log
}

// IsResult implements the validators.Result interface for SarifOutput.
func (*SarifOutput) IsResult() {}
