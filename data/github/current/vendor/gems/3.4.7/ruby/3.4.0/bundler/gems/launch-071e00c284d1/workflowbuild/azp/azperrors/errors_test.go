package azperrors

import (
	"fmt"
	"testing"

	"github.com/github/go-kvp"
	"github.com/stretchr/testify/assert"

	"github.com/github/launch/observability/kvperrors"
)

func TestNewErrorFromAZPResponse_AZPJson(t *testing.T) {
	tests := []struct {
		name    string
		body    []byte
		excType string
		msg     string
		kvp     *kvp.KVP
	}{
		{
			name:    "azp json should return AZPError",
			body:    []byte("{\"$id\":\"1\",\"innerException\":null,\"message\":\"The workflow is not valid. .github/workflows/ci.yml (Line: 29, Col: 9): 'run' is already defined\",\"typeName\":\"Microsoft.TeamFoundation.DistributedTask.Pipelines.PipelineValidationException, Microsoft.TeamFoundation.DistributedTask.WebApi\",\"typeKey\":\"PipelineValidationException\",\"errorCode\":0,\"eventId\":3000}"),
			excType: PipelineValidationException,
			msg:     "The workflow is not valid. .github/workflows/ci.yml (Line: 29, Col: 9): 'run' is already defined",
		},
		{
			name:    "typeKey is all that's needed",
			body:    []byte("{\"typeKey\":\"RunNotFoundException\"}"),
			excType: RunNotFoundException,
			msg:     "",
		},
		{
			name:    "json without typeKey but with a message should return AZPError, with the message and Exception as the type",
			body:    []byte("{ \"message\": \"Github Actions Unavailable. We are working to restore all services as quickly as possible. Please check back soon.\", \"ref\": \"Ref A: 41664332688D4B73864A03108F2FD748 Ref B: ASHEDGE1107 Ref C: 2020-07-07T14:51:40Z\" }"),
			excType: ActionsScaleUnitUnavailable,
			msg:     "Github Actions Unavailable. We are working to restore all services as quickly as possible. Please check back soon.",
			kvp:     kvp.KVPs(kvp.String("ref", "Ref A: 41664332688D4B73864A03108F2FD748 Ref B: ASHEDGE1107 Ref C: 2020-07-07T14:51:40Z")),
		},
		{
			name:    "RerunPlanNotFoundException",
			body:    []byte("{\"$id\":\"1\",\"innerException\":null,\"message\":\"Original plan is no longer available to use in a partial rerun.\",\"typeName\":\"GitHub.Actions.Runtime.WebApi.RerunPlanNotFoundException, GitHub.Actions.Runtime.WebApi\",\"typeKey\":\"RerunPlanNotFoundException\",\"errorCode\":0,\"eventId\":3000,\"stackTrace\":\"   at Microsoft.Azure.Pipelines.Server.ActionsService.RunPipelineAsync(IVssRequestContext requestContext, RunPipelineParameters parameters) ..truncated for test...\"}"),
			excType: RerunPlanNotFoundException,
			msg:     "Original plan is no longer available to use in a partial rerun.",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(tt *testing.T) {
			err := NewErrorFromAZPResponse(test.body, 555)

			assert.IsType(tt, &AZPError{}, err)
			azpErr := err.(*AZPError)
			assert.Equal(tt, test.excType, azpErr.ExceptionType)
			assert.Equal(tt, test.msg, azpErr.Message)
			assert.Equal(tt, 555, azpErr.StatusCode)
			if test.kvp != nil {
				errCtx := kvperrors.Context(err)
				assert.NotNil(tt, errCtx)
				assert.Equal(tt, errCtx, test.kvp)
			}
		})
	}
}

func TestNewErrorFromAZPResponse_UniqueFiltering(t *testing.T) {
	tests := []struct {
		name     string
		message  string
		expected string
	}{
		{
			name:     "filter out an Activity ID",
			message:  "GitHub Actions services are currently unavailable. Try again later. Activity Id: b53b4944-0fb5-49ea-899d-621529a1fabf",
			expected: "GitHub Actions services are currently unavailable. Try again later. Activity Id: ***",
		},
		{
			name:     "filter out a label",
			message:  "A Label with the name ec2-runner already exists.",
			expected: "A Label with the name *** already exists.",
		},
		{
			name:     "filter out an identifier",
			message:  "No runner found with identifier 42363.",
			expected: "No runner found with identifier ***",
		},
		{
			name:     "filter out a UUID",
			message:  "Registration 8d90aec2-ada7-42ce-a698-c7c923b941be is not authorized for host 8d90aec2-ada7-42ce-a698-c7c923b941be",
			expected: "Registration <uuid> is not authorized for host <uuid>",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(tt *testing.T) {
			// Test the AZPError version:
			json := fmt.Sprintf("{\"typeKey\":\"SomeException\",\"message\":\"%s\"}", test.message)
			err := NewErrorFromAZPResponse([]byte(json), 555)

			assert.IsType(tt, &AZPError{}, err)
			assert.Equal(tt, fmt.Sprintf("SomeException: %s (status code: 555)", test.expected), err.Error())

			// Test the AZPRawResponseError version
			err = NewErrorFromAZPResponse([]byte(test.message), 555)

			assert.IsType(tt, &AZPRawResponseError{}, err)
			assert.Equal(tt, fmt.Sprintf("%s (status code: 555)", test.expected), err.Error())

			errCtx := kvperrors.Context(err)
			assert.NotNil(tt, errCtx)
			assert.Equal(tt, errCtx, kvp.KVPs(kvp.String("exception.message", test.message)))
		})
	}
}

func TestNewErrorFromAZPResponse_Other(t *testing.T) {
	tests := []struct {
		name string
		body []byte
		msg  string
	}{
		{
			"invalid json should return AZPRawResponseError",
			[]byte("Someone turned off the internet"),
			"Someone turned off the internet",
		},
		{
			"empty body should return AZPRawResponseError",
			[]byte{},
			"",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(tt *testing.T) {
			err := NewErrorFromAZPResponse([]byte(test.body), 555)

			assert.IsType(tt, &AZPRawResponseError{}, err)
			azpErr := err.(*AZPRawResponseError)
			assert.Equal(tt, test.msg, string(azpErr.Body))
			assert.Equal(tt, 555, azpErr.StatusCode)
		})
	}
}

func TestAZPSyntaxError_Position(t *testing.T) {
	tests := []struct {
		name               string
		syntaxErrorMessage string
		line               int
		col                int
	}{
		{
			name:               "Parses valid error",
			syntaxErrorMessage: "The workflow is not valid. .github/workflows/blank.yaml (Line: 16, Col: 14): Unrecognized function: 'toJson123'. Located at position 1 within expression: toJson123(github)",
			line:               16,
			col:                14,
		},
		{
			name:               "Just position expression",
			syntaxErrorMessage: "(Line: 16, Col: 14):",
			line:               16,
			col:                14,
		},
		{
			name:               "Partial position expression",
			syntaxErrorMessage: "(Line: 16, Col: )",
			line:               -1,
			col:                -1,
		},
		{
			name:               "Empty string",
			syntaxErrorMessage: "",
			line:               -1,
			col:                -1,
		},
		{
			name:               "Random string",
			syntaxErrorMessage: "random string",
			line:               -1,
			col:                -1,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := &AZPSyntaxError{
				SyntaxErrorMessage: tt.syntaxErrorMessage,
			}

			line, col := a.Position()
			if line != tt.line {
				t.Errorf("AZPSyntaxError.Position() got = %v, want %v", line, tt.line)
			}
			if col != tt.col {
				t.Errorf("AZPSyntaxError.Position() got1 = %v, want %v", col, tt.col)
			}
		})
	}
}
