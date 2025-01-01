package cocofix

import (
	"context"
	"fmt"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0/entities"
	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"
)

type FailurePublisher interface {
	PublishAutofixErrorOutcome(context.Context, *tshydro.AutofixErrorOutcome) error
	PublishAutofixInvalidOutcome(context.Context, *tshydro.AutofixInvalidOutcome) error
}

func FixToErrorOutcome(fix *Output, repoID ts.RepositoryEID) (*tshydro.AutofixErrorOutcome, error) {
	if fix.Outcome.Kind != "error" {
		return nil, errors.New(fmt.Sprintf("Invalid fix outcome kind, expected kind 'error', but got '%s'", fix.Outcome.Kind))
	}

	var severity tshydro.AutofixErrorOutcome_ErrorSeverity
	switch fix.Outcome.Severity {
	case OutcomeSeverity_LOW:
		severity = tshydro.AutofixErrorOutcome_LOW
	case OutcomeSeverity_HIGH:
		severity = tshydro.AutofixErrorOutcome_HIGH
	case OutcomeSeverity_CRITICAL:
		severity = tshydro.AutofixErrorOutcome_CRITICAL
	default:
		return nil, errors.New(fmt.Sprintf("Unsupported fix outcome severity: '%s'", fix.Outcome.Severity))
	}

	return &tshydro.AutofixErrorOutcome{
		AutofixVersion: fix.CoCoFixVersion,
		RepositoryId:   uint64(repoID),
		Alert: &tshydro_entities.Alert{
			Message:     fix.Alert.Message,
			RuleId:      fix.Alert.RuleId,
			Path:        fix.Alert.Location.Path,
			StartLine:   uint32(fix.Alert.Location.StartLine),
			StartColumn: uint32(fix.Alert.Location.StartColumn),
			EndLine:     uint32(fix.Alert.Location.EndLine),
			EndColumn:   uint32(fix.Alert.Location.EndColumn),
		},
		Error:       fix.Outcome.Error,
		Description: fix.Outcome.Description,
		Transient:   fix.Outcome.Transient,
		Severity:    severity,
	}, nil
}

func FixToInvalidOutcome(fix *Output, repoID ts.RepositoryEID) (*tshydro.AutofixInvalidOutcome, error) {
	if fix.Outcome.Kind != "fix" {
		return nil, errors.New(fmt.Sprintf("Invalid fix outcome kind, expected kind 'fix', but got '%s'", fix.Outcome.Kind))
	}

	problems := make([]*tshydro.AutofixInvalidOutcome_Problem, len(fix.Outcome.Assessment.Problems))
	for idx, p := range fix.Outcome.Assessment.Problems {

		var problemKind tshydro.AutofixInvalidOutcome_ProblemKind
		switch p.Kind {
		case ProblemKind_NO_CODE_CHANGES:
			problemKind = tshydro.AutofixInvalidOutcome_NO_CODE_CHANGES
		case ProblemKind_SYNTAX_ERROR:
			problemKind = tshydro.AutofixInvalidOutcome_SYNTAX_ERROR
		case ProblemKind_SEMANTIC_ERROR:
			problemKind = tshydro.AutofixInvalidOutcome_SEMANTIC_ERROR
		case ProblemKind_MISSING_DEPENDENCY:
			problemKind = tshydro.AutofixInvalidOutcome_MISSING_DEPENDENCY
		case ProblemKind_VULNERABLE_DEPENDENCY:
			problemKind = tshydro.AutofixInvalidOutcome_VULNERABLE_DEPENDENCY
		default:
			return nil, errors.New(fmt.Sprintf("Unsupported fix outcome problem kind: '%s'", p.Kind))
		}

		problems[idx] = &tshydro.AutofixInvalidOutcome_Problem{
			Kind:        problemKind,
			Description: p.Description,
		}
	}

	return &tshydro.AutofixInvalidOutcome{
		AutofixVersion: fix.CoCoFixVersion,
		RepositoryId:   uint64(repoID),
		Alert: &tshydro_entities.Alert{
			Message:     fix.Alert.Message,
			RuleId:      fix.Alert.RuleId,
			Path:        fix.Alert.Location.Path,
			StartLine:   uint32(fix.Alert.Location.StartLine),
			StartColumn: uint32(fix.Alert.Location.StartColumn),
			EndLine:     uint32(fix.Alert.Location.EndLine),
			EndColumn:   uint32(fix.Alert.Location.EndColumn),
		},
		Problems: problems,
	}, nil
}
