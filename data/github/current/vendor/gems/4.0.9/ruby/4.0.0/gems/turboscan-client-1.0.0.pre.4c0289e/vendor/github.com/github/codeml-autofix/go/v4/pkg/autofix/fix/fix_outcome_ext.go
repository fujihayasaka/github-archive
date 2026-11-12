package fix

import (
	"github.com/github/codeml-autofix/go/v4/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v4/pkg/autofix/utils"
)

// OutcomeKind enumerates high-level fix outcomes.
type OutcomeKind string

// OutcomeKind values identify whether an outcome is a fix or an error.
const (
	OutcomeKindFix   OutcomeKind = "fix"
	OutcomeKindError OutcomeKind = "error"
)

// AllOutcomeKinds lists all valid OutcomeKind values.
var AllOutcomeKinds = []OutcomeKind{OutcomeKindFix, OutcomeKindError}

// IsValidOutcomeKind returns true if the provided string matches a known OutcomeKind.
func IsValidOutcomeKind(kind string) bool {
	return utils.Contains(AllOutcomeKinds, OutcomeKind(kind))
}

// AutofixFixOutput is a convenience alias used when marshaling fix outcomes.
type AutofixFixOutput = []fixdata.Outcome
