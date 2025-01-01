package fix

import (
	"errors"

	"github.com/github/codeml-autofix/go/pkg/autofix/fixdata"
)

type Fix struct {
	Diffs []fixdata.Diff    `json:"diffs"`
	Alert fixdata.RespAlert `json:"alert"`
}

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
