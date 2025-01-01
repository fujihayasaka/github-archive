package common

import (
	"fmt"
	"strings"

	hydro "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
)

func GetWorkflowExecutionId(event *hydro.ComputeUsage) string {
	return fmt.Sprintf("%d.%d", event.WorkflowRunId, event.WorkflowRunAttempt)
}

func GetWorkflowFileName(workflowFilePath string) string {
	if workflowFilePath == "" {
		return ""
	}
	parts := strings.Split(workflowFilePath, "/")
	fileName := parts[len(parts)-1]
	return fileName
}
