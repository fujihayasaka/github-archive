package types

import "fmt"

// WorkflowBackend denotes the backend service that is orchestrating the workflow.
type WorkflowBackend int

const (
	// WorkflowBackendActionsService means that the workflow is being orchestrated by
	// Actions Service (three nines architecture). This is the default.
	// https://github.com/github/actions-dotnet/tree/main/Actions
	WorkflowBackendActionsService WorkflowBackend = iota
	// WorkflowBackendRunService means that the workflow is being orchestrated by
	// Actions Run Service (four nines architecture).
	// https://github.com/github/actions-run-service
	WorkflowBackendRunService

	// WorkflowBackendInconclusive means that we have not decided which backend is
	// orchestrating the workflow.
	// We only know that the workflow is being orchestrated by Actions Service or
	// Run Service once we have resolved the workflow file contents.
	WorkflowBackendInconclusive
)

var workflowBackendStrings = map[WorkflowBackend]string{
	WorkflowBackendActionsService: "ActionsService",
	WorkflowBackendRunService:     "RunService",
	WorkflowBackendInconclusive:   "Inconclusive",
}

func (b WorkflowBackend) String() string {
	if ret, ok := workflowBackendStrings[b]; ok {
		return ret
	}
	return fmt.Sprintf("unknown#%d", b)
}
