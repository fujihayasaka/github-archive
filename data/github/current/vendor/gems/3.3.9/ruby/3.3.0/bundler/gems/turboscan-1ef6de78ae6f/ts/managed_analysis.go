package ts

import (
	"github.com/pkg/errors"
)

// These constants should not be changed, as we rely on them to process messages
// out of hydro. Furthermore we use them to detect whether a workflow is
// triggered by managed analysis.
// If you need to change them, we need to make the WorkflowEventProcessor
// capable of handling multiple WorkflowFilePaths, and change the detection
// of non-managed workflows in should_block_analysis.go
const (
	ManagedAnalysisIntegrationName = "github-code-scanning"
	ManagedAnalysisActionsSlug     = "codeql"
	ManagedAnalysisWorkflowPath    = "dynamic/" + ManagedAnalysisIntegrationName + "/" + ManagedAnalysisActionsSlug
)

var (
	ErrNotOnboarded                 = errors.New("repo is not onboarded")
	ErrNotOnboarding                = errors.New("repo is not onboarding")
	ErrMissingActionsInstallationID = errors.New("Missing Actions Installation ID")
	ErrGHASDisabled                 = errors.New("GHAS is disabled")
	ErrCouldNotResolveRef           = errors.New("could not resolve ref for dynamic workflow")
	ErrSpammyUser                   = errors.New("not running dynamic workflow for spammy user")
	ErrCodeqlRepoNotFound           = errors.New("The codeql repo entry was not found")
	ErrWrongWorkflowRun             = errors.New("workflow run is not the latest validation run")
)
