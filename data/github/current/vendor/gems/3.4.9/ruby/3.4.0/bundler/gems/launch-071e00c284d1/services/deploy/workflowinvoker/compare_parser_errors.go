package workflowinvoker

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	parser "github.com/github/actions-workflow-parser/go"
	"github.com/github/go-kvp"

	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

// Compare parsing errors from actions-dotnet to errors from actions-workflow-parser and log any differences.
func (i *buildInvoker) compareParserErrors(ctx context.Context, wf *parser.WorkflowTemplate, azpErr error) {
	if wf == nil {
		return
	}

	i.obs.Debug(ctx, "comparing parsing errors")

	// If the error from actions-dotnet is not an AZPSyntaxError, treat it as nil for comparison
	if azpErr != nil {
		if _, ok := azpErr.(*azperrors.AZPSyntaxError); !ok {
			azpErr = nil
		}
	}

	// Recover from and report any panics
	defer func() {
		if r := recover(); r != nil {
			e, ok := r.(error)
			if !ok {
				e = fmt.Errorf("%v", r)
			}

			err := fmt.Errorf("panic comparing errors between actions-workflow-parser and actions-dotnet: %w", e)
			i.obs.Report(ctx, err)
		}
	}()

	wfpErr := wfparser.CheckErrors(wf)

	if wfpErr == nil && azpErr == nil {
		i.obs.Debug(ctx, "no parsing errors")
		return
	}

	if equal, errorCategory, wontFix := diffErrors(wfpErr, azpErr); !equal {
		i.obs.Debug(ctx, "parsing errors from actions-workflow-parser and actions-dotnet are different", kvp.String("gh.launch.azp_error", errorString(azpErr)), kvp.String("exception.message", errorString(wfpErr)), kvp.String("exception.type", errorCategory), kvp.String("gh.launch.wont_fix", strconv.FormatBool(wontFix)))
		i.obs.Observability.Counter(ctx, "compare_parse_errors", statter.Tags{"errors_same": strconv.FormatBool(false), "exception.type": errorCategory, "wont_fix": strconv.FormatBool(wontFix)}, 1)
		return
	}

	i.obs.Debug(ctx, "parsing errors from actions-workflow-parser and actions-dotnet are the same")
	i.obs.Observability.Counter(ctx, "compare_parse_errors", statter.Tags{"errors_same": strconv.FormatBool(true)}, 1)
}

func errorString(err error) string {
	if err != nil {
		return err.Error()
	}
	return "<nil>"
}

// returns if the errors are equal, the error category, and if this is a wontFix
func diffErrors(wfpErr, azpErr error) (bool, string, bool) {
	if errorsAreDifferent(wfpErr, azpErr) {
		c, wontFix := errorDiffCategory(wfpErr, azpErr)
		return false, c, wontFix
	}
	return true, "", false
}

func errorsAreDifferent(wfpErr, azpErr error) bool {
	return wfpErr == nil || azpErr == nil || wfpErr.Error() != azpErr.Error()
}

// errorDiffCategory tries to loosely categorize the difference between the errors
// Returns the categories and if this is a wontFix
func errorDiffCategory(wfpErr, azpErr error) (string, bool) {
	categories := []string{}

	// AZP had an error but WFP did not
	if wfpErr == nil {
		categories = append(categories, "azp_only")
	}

	// WFP had an error but AZP did not
	if azpErr == nil {
		categories = append(categories, "wfp_only")
	}

	// Check if errors are syntax and parsing errors
	azp, azpOk := azpErr.(*azperrors.AZPSyntaxError)
	if azpErr != nil && !azpOk {
		categories = append(categories, "not_azp_syntax_error")
	}

	wfp, wfpOk := wfpErr.(*wfparser.WorkflowParseError)
	if wfpErr != nil && !wfpOk {
		// This should never happen
		categories = append(categories, "not_wfp_parse_error")
	}

	if wfpErr == nil || azpErr == nil || !azpOk || !wfpOk {
		return strings.Join(categories, "|"), false
	}

	azpErrs := separateAzpErrs(azp)

	wfpErrs := wfp.Errors

	// For each pair of errors, check if they meet any of the error categories
	for i := 0; i < len(azpErrs) || i < len(wfpErrs); i++ {
		wMsg, aMsg := "", ""
		wfpLine, wfpCol, azpLine, azpCol := -1, -1, -1, -1

		// If there is a mismatch in the number of errors, treat the missing error as empty
		if i < len(azpErrs) {
			aMsg = azpErrs[i].Error()
			// This cast should always succeed
			if p, ok := azpErrs[i].(*azperrors.AZPSyntaxError); ok {
				azpLine, azpCol = p.Position()
			}
		}
		if i < len(wfpErrs) {
			wMsg = wfpErrs[i].Error()
			// This cast should always succeed
			if p, ok := wfpErrs[i].(wfparser.Positioner); ok {
				_, wfpLine, wfpCol = p.Position()
			}
		}

		// Ignoring the file, currently assuming they are the same
		if wMsg != "" && aMsg != "" && azpLine == wfpLine && azpCol == wfpCol {
			if aMsg == wMsg {
				// One of the errors was the same
				continue
			}
			categories = append(categories, "same_position")
			c, wontFix := findCategory(samePosErrorCategories, wMsg, aMsg)
			if c != "" {
				categories = append(categories, c)
				return strings.Join(categories, "|"), wontFix
			}
		} else {
			categories = append(categories, "different_position")
			c, wontFix := findCategory(differentPosErrorCategories, wMsg, aMsg)
			if c != "" {
				categories = append(categories, c)
				return strings.Join(categories, "|"), wontFix
			}
		}
	}

	return strings.Join(categories, "|"), false
}

// Returns category matching the provided errors and if it is a wontFix
// If no match, returns empty string and false
func findCategory(ec []errorCategory, wfpErr, azpErr string) (string, bool) {
	for _, category := range ec {
		isAzpMatch, isWfpMatch := false, false

		if category.azpMatch == nil {
			isAzpMatch = true
		} else {
			for _, azpMatch := range category.azpMatch {
				if strings.Contains(azpErr, azpMatch) {
					isAzpMatch = true
					break
				}
			}
		}

		if category.wfpMatch == nil {
			isWfpMatch = true
		} else {
			for _, wfpMatch := range category.wfpMatch {
				if strings.Contains(wfpErr, wfpMatch) {
					isWfpMatch = true
					break
				}
			}
		}

		if isAzpMatch && isWfpMatch {
			if category.other != nil {
				if !category.other(azpErr, wfpErr) {
					continue
				}
			}

			return category.desc, category.wontFix
		}
	}

	return "", false
}

// This method separates the azp error into two errors if it contains two errors
func separateAzpErrs(azpErr *azperrors.AZPSyntaxError) []error {
	// Remove prefix if present
	pref := "The workflow is not valid. "
	errMsg := strings.TrimPrefix(azpErr.Error(), pref)

	lastErrIndx := strings.LastIndex(errMsg, ".github/")
	if lastErrIndx == -1 {
		// Error did not contain file name, return as is
		return []error{azperrors.NewInvalidSyntaxError(errMsg)}
	}

	if lastErrIndx != 0 {
		// Two errors, split and return
		err1 := azperrors.NewInvalidSyntaxError(strings.TrimSpace(errMsg[:lastErrIndx]))
		err2 := azperrors.NewInvalidSyntaxError(errMsg[lastErrIndx:])
		return []error{err1, err2}
	}

	// Only 1 error, return as is
	return []error{azperrors.NewInvalidSyntaxError(errMsg)}
}

type errorCategory struct {
	desc     string
	azpMatch []string      // substrings contained in the azp error
	wfpMatch []string      // substrings contained in the wfp error
	other    otherCriteria // other criteria to match
	wontFix  bool
}

type otherCriteria func(string, string) bool

// Error categories that require the same position in the workflow file
var samePosErrorCategories = []errorCategory{
	{
		// https://github.com/github/c2c-actions-experience/issues/6951
		// Errors in expression engine - C# returns a parsing error before Go returns a lexing error
		desc: "expression_engine_ordering",
		azpMatch: []string{
			"Unexpected symbol",
			"Unrecognized named-value",
			"Unexpected end of expression",
			"Exceeded max expression depth",
			"Unrecognized named-value",
			"Unrecognized function",
		},
		wfpMatch: []string{
			"Unexpected symbol",
			"Exceeded max expression length",
			"Too few parameters supplied",
			"Too many parameters supplied",
		},
		other: func(azpErr, wfpErr string) bool {
			// Check position of error in expression, azpErr should be before wfpErr
			posRegex := regexp.MustCompile(`Located at position (\d+) within expression`)
			azpPosMatches := posRegex.FindStringSubmatch(azpErr)
			if len(azpPosMatches) < 2 {
				return false
			}
			azpPos := azpPosMatches[1]
			wfpPosMatches := posRegex.FindStringSubmatch(wfpErr)
			if len(wfpPosMatches) < 2 {
				return false
			}
			wfpPos := wfpPosMatches[1]

			return azpPos < wfpPos
		},
		wontFix: true,
	},
	{
		// https://github.com/github/c2c-actions-experience/issues/7052
		// C# includes new lines in error messages, Go does not
		desc: "azp_new_lines",
		other: func(azpErr, wfpErr string) bool {
			// See if the difference between the errors is just new lines
			azp := strings.ReplaceAll(azpErr, "\n", "")
			return azp == wfpErr
		},
		wontFix: true,
	},
	{
		// https://github.com/github/c2c-actions-experience/issues/7002
		// `Too many parameters supplied` error uses different tokens in expression
		desc: "too_many_parameters",
		azpMatch: []string{
			"Too many parameters supplied",
		},
		wfpMatch: []string{
			"Too many parameters supplied",
		},
		wontFix: true,
	},
	{
		// https://github.com/github/c2c-actions-experience/issues/7002
		// `Too few parameters` error uses different tokens in expression
		desc: "too_few_parameters",
		azpMatch: []string{
			"Too few parameters supplied",
		},
		wfpMatch: []string{
			"Too few parameters supplied",
		},
		wontFix: true,
	},
	{
		// https://github.com/github/c2c-actions-experience/issues/6973
		// C# returns an exception `Input string was not in a correct format` that shows as a parsing error.
		// This covers when this is appended to an error
		desc: "input_string_exception",
		other: func(azpErr, wfpErr string) bool {
			return azpErr == wfpErr+" Input string was not in a correct format."
		},
		wontFix: true,
	},
	{
		// https://github.com/github/c2c-actions-experience/issues/6971
		// C# scrubs out secrets from error messages, Go does not
		// Secret masks from https://github.com/github/actions-dotnet/blob/a12ccfc67b913d81657f36cafe2457252abe34e8/Vssf/Client/Common/Utility/SecretUtility.cs#L19-L38
		desc: "secret_scrubbing",
		azpMatch: []string{
			"******",
			"<secret removed>",
			"<signature removed>",
			"**password-removed**",
			"**pwd-removed**",
			"**password-space-removed**",
			"**pwd-space-removed**",
			"**account-key-removed**",
		},
		wontFix: true,
	},
	{
		// https://github.com/github/actions-build/issues/62
		// C# scrubs out uuids from error messages, Go does not
		// Issue on actions runtime for doing the same in four-nines: https://github.com/github/actions-runtime/issues/4101
		desc: "uuid_scrubbing",
		azpMatch: []string{
			"<uuid>",
		},
		wontFix: true,
	},
}

// Error categories that require different position in the file
var differentPosErrorCategories = []errorCategory{
	{
		// https://github.com/github/c2c-actions-experience/issues/6973
		// C# returns an exception `Input string was not in a correct format` that shows as a parsing error.
		// This covers when this string is a separate error
		desc: "input_string_exception",
		other: func(azpErr, wfpErr string) bool {
			return wfpErr == "" && strings.Contains(azpErr, "Input string was not in a correct format.")
		},
		wontFix: true,
	},
	{
		// https://github.com/github/actions-build/issues/217
		// Error when evaluating concurrency with an empty value
		desc: "concurrency_error_empty",
		azpMatch: []string{
			"Unexpected value ''",
		},
		wfpMatch: []string{
			"Unexpected value ''",
		},
		other: func(azpErr, wfpErr string) bool {
			return strings.Contains(wfpErr, "Error when evaluating 'concurrency'")
		},
		wontFix: true,
	},
	{
		desc: "concurrency_error_max_group_name_size_exceeded",
		azpMatch: []string{
			"Maximum object size exceeded",
		},
		wfpMatch: []string{
			"Concurrency group name must be less than 400 characters",
		},
		wontFix: true,
	},
}
