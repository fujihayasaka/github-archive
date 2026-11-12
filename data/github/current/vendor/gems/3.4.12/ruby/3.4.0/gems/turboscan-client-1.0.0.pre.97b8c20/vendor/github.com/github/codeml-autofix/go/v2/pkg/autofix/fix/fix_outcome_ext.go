package fix

import (
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
)

// OutcomeKind enumerates high-level fix outcomes.
type OutcomeKind string

const (
	OutcomeKind_FIX   = "fix"
	OutcomeKind_ERROR = "error"
)

// AllOutcomeKinds lists all valid OutcomeKind values.
var AllOutcomeKinds = []OutcomeKind{OutcomeKind_FIX, OutcomeKind_ERROR}

// IsValidOutcomeKind returns true if the provided string matches a known OutcomeKind.
func IsValidOutcomeKind(kind string) bool {
	return utils.Contains(AllOutcomeKinds, OutcomeKind(kind))
}

// AutofixFixOutput is a convenience alias used when marshaling fix outcomes.
type AutofixFixOutput = []fixdata.Outcome
