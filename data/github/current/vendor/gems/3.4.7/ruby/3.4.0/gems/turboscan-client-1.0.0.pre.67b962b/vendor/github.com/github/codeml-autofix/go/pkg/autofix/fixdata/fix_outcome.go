// Package fix provides a type that represents the response from the autofix service.
// FOTIS: Initially copied over from Turboscan, with minor modifications.
// https://github.com/github/codeql-core/issues/4785#issuecomment-2640460813 for reference.
package fixdata

import (
	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/pkg/autofix/codebase"
)

type AutofixResponse []Output

func NewAutofixResponse(version string, alert alerts.Alert, outcome Outcome) AutofixResponse {
	// Create the alert representation
	alertResp := RespAlert{
		ID:       alert.ID,
		Message:  alert.Message,
		RuleId:   alert.GetRule().ID,
		Location: FromSourceLocation(alert.Location),
	}

	return []Output{
		{
			AutofixVersion: version,
			Alert:          alertResp,
			Outcome:        outcome,
		},
	}
}

// The outcome of trying to fix an alert (either a proposed fix, or an error),
// in a format suitable for JSON serialization.
type Output struct {
	AutofixVersion string    `json:"autofixVersion"`
	Alert          RespAlert `json:"alert,omitempty"`
	Outcome        Outcome   `json:"outcome"`
}

type RespAlert struct {
	// ID is the alerts unique identifier. This is only set when the library's
	// client provides an alert ID. When the alert is created by converting a
	// SARIF, this is set to the result GUID.
	ID       string   `json:"id"`
	Message  string   `json:"message"`
	RuleId   string   `json:"ruleId"`
	Location Location `json:"location"`
}

type OutcomeKind string

const (
	OutcomeKind_FIX   OutcomeKind = "fix"
	OutcomeKind_ERROR OutcomeKind = "error"
)

// A proposed fix for an alert (as opposed to an error), in a format suitable
// for JSON serialization.
type Outcome struct {
	// kind: fix|error
	Kind OutcomeKind `json:"kind"`
	// The edits comprising the fix
	Diffs      []Diff     `json:"diffs,omitempty"`
	Assessment Assessment `json:"assessment,omitempty"`
	Details    Details    `json:"details,omitempty"`

	// AutofixError is the structured autofix error. This is not serialized to JSON.
	AutofixError autofix.AutofixError

	// The error message, if `kind` is 'error'.
	Error string `json:"error,omitempty"`
	// Whether the error is transient, if `kind` is 'error'.
	Transient bool `json:"transient,omitempty"`
}

func NewErrorOutcome(err autofix.AutofixError) Outcome {
	// Handle the error case
	return Outcome{ //nolint:exhaustruct
		Kind:         OutcomeKind_ERROR,
		AutofixError: err,
		Error:        err.Error(),
		Transient:    err.Retryable(),
	}
}

type Diff struct {
	Path string `json:"path,omitempty"`
	Diff string `json:"diff,omitempty"`
}

type Rule struct {
	ID string `json:"id"`
}

type Location struct {
	Path        string `json:"path"`
	StartLine   int    `json:"startLine"`
	StartColumn int    `json:"startColumn"`
	EndLine     int    `json:"endLine"`
	EndColumn   int    `json:"endColumn"`
}

func FromSourceLocation(loc codebase.SourceLocation) Location {
	return Location{
		Path:        loc.File.Path,
		StartLine:   int(loc.StartLine()),
		StartColumn: int(loc.StartColumn()),
		EndLine:     int(loc.EndLine()),
		EndColumn:   int(loc.EndColumn()),
	}
}

type AssessmentOutcome string

const (
	AssessmentOutcome_VALID   AssessmentOutcome = "valid"
	AssessmentOutcome_INVALID AssessmentOutcome = "invalid"
)

// The outcome of checking whether a fix suggestion is valid.
//
// For invalid fixes, `problems` is a list of potential reasons why the fix is
// invalid.
//
// Iff outcome is 'valid', `problems` is an empty list.
type Assessment struct {
	Outcome  AssessmentOutcome `json:"outcome,omitempty"`
	Problems []Problem         `json:"problems,omitempty"`
}

type ProblemKind string

const (
	ProblemKind_NO_CODE_CHANGES       ProblemKind = "no code changes"
	ProblemKind_SYNTAX_ERROR          ProblemKind = "syntax error"
	ProblemKind_SEMANTIC_ERROR        ProblemKind = "semantic error"
	ProblemKind_MISSING_DEPENDENCY    ProblemKind = "missing dependency"
	ProblemKind_VULNERABLE_DEPENDENCY ProblemKind = "vulnerable dependency"
)

type Problem struct {
	Kind        ProblemKind `json:"kind"`
	Description string      `json:"description"`
}

type Details struct {
	// A natural-language description of the fix.
	FixDescription string `json:"fixDescription,omitempty"`
	// Information about any dependencies added by the fix.
	DependencyMetadata []DependencyMetadata `json:"dependencyMetadata,omitempty"`
}

type DependencyMetadata struct {
	Name        string     `json:"name"`
	Version     string     `json:"version"`
	Ecosystem   string     `json:"ecosystem"`
	Description string     `json:"description,omitempty"`
	Url         string     `json:"url,omitempty"`
	IsMalicious bool       `json:"isMalicious,omitempty"`
	Advisories  []Advisory `json:"advisories,omitempty"`
}

type Advisory struct {
	// The advisory's ID.
	Id string `json:"ghsa_id"`
	// The URL of the advisory on GitHub.
	HtmlUrl string `json:"html_url"`
	// A brief description of the advisory.
	Summary string `json:"summary"`
	// A longer description of the advisory, if	available.
	Description string `json:"description,omitempty"`
	// The severity of the advisory.
	Severity string `json:"severity"`
}
