// Package fix defines structures and helpers for representing a single
// fix, in the autovalidation system.
package fix

import (
	"github.com/pkg/errors"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
)

// Fix represents a single fix candidate produced by autofix used in
// autovalidation.
type Fix struct {
	Diffs []fixdata.Diff    `json:"diffs"`
	Alert fixdata.RespAlert `json:"alert"`
}

// FromAutofixResponse converts a single-output AutofixResponse into a Fix.
// Returns an error if the response is nil or doesn't contain exactly one output.
func FromAutofixResponse(response *fixdata.AutofixResponse) (*Fix, error) {
	if response == nil {
		return nil, errors.New("response is nil")
	}

	outputs := []fixdata.Output(*response)

	if len(outputs) != 1 {
		return nil, errors.New("response should contain exactly one output")
	}

	outcome := outputs[0].Outcome
	alert := outputs[0].Alert

	return &Fix{
		Diffs: outcome.Diffs,
		Alert: alert,
	}, nil
}
