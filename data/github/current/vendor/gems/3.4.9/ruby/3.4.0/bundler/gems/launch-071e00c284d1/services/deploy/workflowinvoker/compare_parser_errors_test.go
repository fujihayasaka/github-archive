package workflowinvoker

import (
	"context"
	"fmt"

	"github.com/stretchr/testify/require"

	"github.com/github/actions-expressions/go/data"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

const (
	wfExprNotClosed = `
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ github.event_name
`
	wfNoError = `
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: echo Hello World
`
	wfUnexpectedSymbol = `
on: push
jobs:
  build:
    if: "${{ 1 = 2 }}"
    runs-on: linux
    steps:
      - run: echo hi
`
	wfUnexpectedValue = `
on: push
jobs:
  build:
    runs-on: linux
    with:
`
	wfTooManyParameters = `
on: push
jobs:
  build:
    if: contains('a', 'b', 'c')
    runs-on: linux
    steps:
      - run: echo hi
`
	wfExpectedFormat = `
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/@v1
`
	wfEmptyConcurrency = `
on: workflow_dispatch
concurrency:
  group: ''
  cancel-in-progress: true
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/@v1
`
	wfConcurrencyMaxObjectSizeExceeded = `
on: workflow_dispatch
concurrency:
  group: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  cancel-in-progress: true
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Hello, world!"
`
)

// These tests are intended to test if logs are logged as expected.
// Errors from actions-dotnet for the given workflows are not all accurate to production.
func (s *buildInvokerTest) TestCompareParserErrors() {
	tests := []struct {
		desc             string
		azpErr           error
		workflow         string
		expectErrors     bool
		expectSameErrors bool
		errorCategory    string
		wontFix          bool
		concurrencyCheck bool
		concurrencyNil   bool
	}{
		{
			desc: "same errors",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/workflow.yml (Line: 7, Col: 14): The expression is not closed. An unescaped ${{ sequence was found, but the closing }} sequence was not found.",
			},
			workflow:         wfExprNotClosed,
			expectErrors:     true,
			expectSameErrors: true,
		},
		{
			desc: "different errors - different error messages, different position",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/invalid.yml (Line: 1, Col: 1): Unexpected value 'on'",
			},
			workflow:         wfExprNotClosed,
			expectErrors:     true,
			expectSameErrors: false,
			errorCategory:    "different_position",
		},
		{
			desc:             "different errors - azp error is nil",
			azpErr:           nil,
			workflow:         wfExprNotClosed,
			expectErrors:     true,
			expectSameErrors: false,
			errorCategory:    "wfp_only",
		},
		{
			desc: "different errors - wfp error is nil",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: ".github/workflows/expression-not-closed.yml (Line: 6, Col: 14): The expression is not closed. An unescaped ${{ sequence was found, but the closing }} sequence was not found.",
			},
			workflow:         wfNoError,
			expectErrors:     true,
			expectSameErrors: false,
			errorCategory:    "azp_only",
		},
		{
			desc:         "no errors",
			azpErr:       nil,
			workflow:     wfNoError,
			expectErrors: false,
		},
		{
			desc:         "no errors - azp error is different error type",
			azpErr:       azperrors.NewRerunPlanNotFoundError("not a parsing error"),
			workflow:     wfNoError,
			expectErrors: false,
		},
		{
			desc: "expression_engine_ordering",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/invalid.yml (Line: 5, Col: 9): Unexpected symbol: '<something-different-from-wfp>' Located at position 1 within expression within expression: 1 = 2",
			},
			workflow:      wfUnexpectedSymbol,
			expectErrors:  true,
			errorCategory: "same_position|expression_engine_ordering",
			wontFix:       true,
		},
		{
			desc: "azp_new_lines",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/workflow.yml (Line: 6, Col: 5): Unexpected value 'with\n'",
			},
			workflow:      wfUnexpectedValue,
			expectErrors:  true,
			errorCategory: "same_position|azp_new_lines",
			wontFix:       true,
		},
		{
			desc: "too_many_parameters",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/workflow.yml (Line: 5, Col: 9): Too many parameters supplied: '('. Located at position 9 within expression: contains('a', 'b', 'c')",
			},
			workflow:      wfTooManyParameters,
			expectErrors:  true,
			errorCategory: "same_position|too_many_parameters",
			wontFix:       true,
		},
		{
			desc: "input_string_exception same position",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/workflow.yml (Line: 7, Col: 15): Expected format {org}/{repo}[/path]@ref. Actual 'actions/@v1' Input string was not in a correct format.",
			},
			workflow:      wfExpectedFormat,
			expectErrors:  true,
			errorCategory: "same_position|input_string_exception",
			wontFix:       true,
		},
		{
			desc: "input_string_exception different position",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/workflow.yml (Line: 7, Col: 15): Expected format {org}/{repo}[/path]@ref. Actual 'actions/@v1' .github/workflows/workflow.yml Input string was not in a correct format.",
			},
			workflow:      wfExpectedFormat,
			expectErrors:  true,
			errorCategory: "different_position|input_string_exception",
			wontFix:       true,
		},
		{
			desc: "secret_scrubbing",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/workflow.yml (Line: 6, Col: 5): Unexpected value **password-removed**",
			},
			workflow:      wfUnexpectedValue,
			expectErrors:  true,
			errorCategory: "same_position|secret_scrubbing",
			wontFix:       true,
		},
		{
			desc: "uuid_scrubbing",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/workflow.yml (Line: 6, Col: 5): Unrecognized named-value: '<uuid>'. Located at position 1 within expression: <uuid>",
			},
			workflow:      wfUnexpectedValue,
			expectErrors:  true,
			errorCategory: "same_position|uuid_scrubbing",
			wontFix:       true,
		},
		{
			desc: "concurrency_error_empty",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. .github/workflows/workflow.yml (Line: 4, Col: 10): Unexpected value ''",
			},
			workflow:         wfEmptyConcurrency,
			expectErrors:     true,
			expectSameErrors: true,
			errorCategory:    "different_position|concurrency_error_empty",
			wontFix:          true,
			concurrencyCheck: true,
			concurrencyNil:   true,
		},
		{
			desc: "concurrency_error_max_group_name_size_exceeded",
			azpErr: &azperrors.AZPSyntaxError{
				SyntaxErrorMessage: "The workflow is not valid. Maximum object size exceeded",
			},
			workflow:         wfConcurrencyMaxObjectSizeExceeded,
			expectErrors:     true,
			expectSameErrors: false,
			errorCategory:    "different_position|concurrency_error_max_group_name_size_exceeded",
			wontFix:          true,
			concurrencyCheck: true,
		},
	}

	for _, tt := range tests {
		s.Run(tt.desc, func() {
			s.recordingLogger.Reset()

			workflowFilePath := ".github/workflows/workflow.yml"
			resolvedFiles := []wfparser.WorkflowReferencedFile{
				{
					Path: workflowFilePath,
					Text: tt.workflow,
				},
			}

			ctx := context.Background()
			obs := observability.NewNullObservability()

			wf, err := wfparser.LoadWorkflow(ctx, obs, workflowFilePath, wfparser.NewFileProvider(ctx, obs, resolvedFiles), types.LimitedReadWorkflowPermissions)
			require.NoError(s.T(), err)

			if tt.concurrencyCheck {
				concurrency := wfparser.EvaluateWorkflowConcurrency(ctx, obs, wf, workflowFilePath, data.NewDictionary())

				if tt.concurrencyNil {
					require.Nil(s.T(), concurrency)
				}
			}

			s.invoker.compareParserErrors(context.Background(), wf, tt.azpErr)
			if tt.expectErrors {
				if tt.expectSameErrors {
					s.assertLogged("parsing errors from actions-workflow-parser and actions-dotnet are the same")
				} else {
					s.assertLogged("parsing errors from actions-workflow-parser and actions-dotnet are different")
					if tt.errorCategory != "" {
						s.assertLogged(fmt.Sprintf("exception.type=%s", tt.errorCategory))
					}
					if tt.wontFix {
						s.assertLogged("wont_fix=true")
					} else {
						s.assertLogged("wont_fix=false")
					}
				}
			} else {
				s.assertLogged("no parsing errors")
				if tt.errorCategory != "" {
					s.Fail("should not expect error category if not expecting errors")
				}
				if tt.wontFix {
					s.Fail("should not expect wontFix if not expecting errors")
				}
			}
		})
	}
}

func (s *buildInvokerTest) TestSeparateAzpErrs() {
	tests := []struct {
		desc      string
		azpErrMsg string
		expected  []string
	}{
		{
			desc:      "one error",
			azpErrMsg: "The workflow is not valid. .github/workflows/ci.yml (Line: 1, Col: 1): error message",
			expected: []string{
				".github/workflows/ci.yml (Line: 1, Col: 1): error message",
			},
		},
		{
			desc:      "two errors",
			azpErrMsg: "The workflow is not valid. .github/workflows/ci.yml (Line: 1, Col: 1): error message 1 .github/workflows/ci.yml (Line: 2, Col: 1): error message 2",
			expected: []string{
				".github/workflows/ci.yml (Line: 1, Col: 1): error message 1",
				".github/workflows/ci.yml (Line: 2, Col: 1): error message 2",
			},
		},
		{
			desc:      "error with no file name",
			azpErrMsg: "error message",
			expected: []string{
				"error message",
			},
		},
	}
	for _, tt := range tests {
		s.Run(tt.desc, func() {
			azpErr := &azperrors.AZPSyntaxError{SyntaxErrorMessage: tt.azpErrMsg}
			actual := separateAzpErrs(azpErr)
			require.Equal(s.T(), len(tt.expected), len(actual))
			for i, expected := range tt.expected {
				require.Equal(s.T(), expected, actual[i].Error())
			}

		})
	}
}
