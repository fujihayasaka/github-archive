package launcher

import (
	"fmt"
	"strings"

	parser "github.com/github/actions-workflow-parser/go"
	"github.com/github/actions-workflow-parser/go/template"
)

// workflowPath is the path used for single-file workflow validation.
const workflowPath = ".github/workflows/workflow.yml"

// SimpleFileProvider implements parser.FileProvider for single-file validation.
// It provides the workflow content as if it were a file at the workflowPath.
type SimpleFileProvider struct {
	content string
}

// NewSimpleFileProvider creates a new SimpleFileProvider with the given content.
func NewSimpleFileProvider(content string) *SimpleFileProvider {
	return &SimpleFileProvider{
		content: content,
	}
}

// GetFileContents returns the file content for the given path.
func (p *SimpleFileProvider) GetFileContents(_ string) (string, error) {
	return p.content, nil
}

// GetFileInfo returns file metadata for the given path.
func (p *SimpleFileProvider) GetFileInfo(filePath string) (*parser.FileInfo, error) {
	return &parser.FileInfo{Path: filePath}, nil
}

// WorkflowValidationError represents a validation error from the workflow parser.
type WorkflowValidationError struct {
	Message string
	Line    int
	Column  int
}

func (e *WorkflowValidationError) Error() string {
	if e.Line > 0 {
		return fmt.Sprintf("line %d: %s", e.Line, e.Message)
	}
	return e.Message
}

// WorkflowValidationResult contains the result of workflow validation.
type WorkflowValidationResult struct {
	Valid  bool
	Errors []WorkflowValidationError
}

// FullError returns a detailed error message with all validation errors.
func (r *WorkflowValidationResult) FullError() string {
	if r.Valid || len(r.Errors) == 0 {
		return ""
	}

	var sb strings.Builder
	_, _ = sb.WriteString("workflow validation failed:\n")
	for i, err := range r.Errors {
		_, _ = sb.WriteString(fmt.Sprintf("  %d. %s\n", i+1, err.Error()))
	}
	return sb.String()
}

// validateWorkflowYAML validates a workflow YAML string using the actions-workflow-parser.
// It returns a WorkflowValidationResult containing validation status and any errors.
func validateWorkflowYAML(yamlContent string) *WorkflowValidationResult {
	fileProvider := NewSimpleFileProvider(yamlContent)

	parseOptions := func(opts *template.ParseOptions) {
		// Skip reusable workflows since we're validating a single file
		opts.SkipReusableWorkflows = true
		// Include event configs so dynamic trigger is validated
		opts.IncludeEventConfigs = true
	}

	result := &WorkflowValidationResult{
		Valid:  true,
		Errors: []WorkflowValidationError{},
	}

	workflow, err := parser.LoadWorkflow(
		fileProvider,
		workflowPath,
		parser.PermissionsPolicyLimitedRead,
		parseOptions,
	)

	// Handle load error
	if err != nil {
		result.Valid = false
		result.Errors = append(result.Errors, WorkflowValidationError{
			Message: err.Error(),
		})
		return result
	}

	// Check for validation errors in the parsed workflow
	if workflow != nil && len(workflow.Errors) > 0 {
		result.Valid = false
		for _, e := range workflow.Errors {
			result.Errors = append(result.Errors, WorkflowValidationError{
				Message: e.Error(),
			})
		}
	}

	return result
}
