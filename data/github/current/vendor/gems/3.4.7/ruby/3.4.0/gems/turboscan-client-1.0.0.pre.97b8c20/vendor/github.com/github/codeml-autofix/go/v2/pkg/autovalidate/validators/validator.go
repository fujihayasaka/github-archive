// Package validators provides interfaces and implementations for validating AutoFix results.
package validators

import (
	"context"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/exec"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/fix"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/output"
)

// Result is a marker interface for all validator result types.
type Result interface {
	IsResult()
}

// Validator interface defines all validation related contracts
type Validator interface {
	SupportedOutputFormats() []output.Format
	Validate(ctx context.Context, autofix *fix.Fix, codeBase codebase.VirtualCodebase, env exec.CommandEnvironment, outputFormat output.Format) (Result, error)
}
