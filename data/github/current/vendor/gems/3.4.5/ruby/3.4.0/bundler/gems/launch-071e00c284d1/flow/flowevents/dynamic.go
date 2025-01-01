package flowevents

import (
	"path/filepath"
	"strings"

	"github.com/shurcooL/githubv4"
)

const DynamicWorkflowFilePath = "dynamic"

func BuildDynamicWorkflowFilePath(app, slug string) string {
	return filepath.Join(DynamicWorkflowFilePath, app, slug)
}

// ExtractDynamicWorkflowFilePath returns the integration name and slug if the workflow file path is well formed and a dynamic path.
func ExtractDynamicWorkflowFilePath(path string) (integrator, slug string, ok bool) {
	// dynamic/pages/pages-build-deployment
	parts := strings.Split(path, "/")

	if len(parts) != 3 {
		return "", "", false
	}

	if parts[0] != DynamicWorkflowFilePath {
		return "", "", false
	}

	return parts[1], parts[2], true
}

// DynamicEvent is passed as a GitHubEvent
type DynamicEvent struct {
	// Ref is the ref to run the workflow against
	Ref string `json:"ref,omitempty"`

	// Workflow is the workflow YAML to run
	Workflow string `json:"workflow,omitempty"`

	// IntegrationName is the name of the integration that triggered this event
	IntegrationName string `json:"integration_name,omitempty"`

	// Inputs provided for the workflow
	Inputs map[string]string `json:"inputs,omitempty"`

	// WorkflowName is the name of the workflow
	WorkflowName string `json:"workflow_name,omitempty"`

	// Slug is used to form the filename of the workflow
	Slug string `json:"slug,omitempty"`

	// Indicates whether the details of this workflow
	// should be visible outside of the Actions tab
	Visibility githubv4.CheckSuiteVisibility `json:"visibility,omitempty"`

	Enterprise   map[string]interface{} `json:"enterprise,omitempty"`
	Repository   map[string]interface{} `json:"repository,omitempty"`
	Organization map[string]interface{} `json:"organization,omitempty"`
}
