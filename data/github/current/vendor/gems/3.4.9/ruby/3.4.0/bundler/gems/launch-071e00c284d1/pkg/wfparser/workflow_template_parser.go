package wfparser

import (
	"context"
	"errors"
	"fmt"
	"strings"

	parser "github.com/github/actions-workflow-parser/go"
	"github.com/github/actions-workflow-parser/go/template"

	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/requiredworkflowutils"
)

func LoadWorkflow(ctx context.Context, obs *observability.Observability, workflowFilePath string, fileProvider parser.FileProvider,
	permissionsPolicy types.DefaultWorkflowPermissions, parseOptions ...func(*template.ParseOptions)) (wf *parser.WorkflowTemplate, err error) {
	// Recover from and report any panics from the parser
	defer func() {
		if r := recover(); r != nil {
			e, ok := r.(error)
			if !ok {
				e = fmt.Errorf("%v", r)
			}

			err = fmt.Errorf("panic loading workflow from actions-workflow-parser: %w", e)
			obs.Report(ctx, err)
		}
	}()

	// Convert permissions policy
	policy, err := toParserPermissionPolicy(permissionsPolicy)
	if err != nil {
		return nil, err
	}

	workflowFilePath = requiredworkflowutils.RemoveMetadataFromRequiredWorkflowPath(workflowFilePath)

	// Load workflow
	wf, err = parser.LoadWorkflow(fileProvider, workflowFilePath, policy, parseOptions...)
	if err != nil {
		return nil, err
	}

	// Check for NotImplementedErrors, return error aggregating all unimplemented features if any
	var notImplemented []string
	for _, wfErr := range wf.Errors {
		var ner *template.NotImplementedError
		if errors.As(wfErr, &ner) {
			notImplemented = append(notImplemented, ner.Key)
		}
	}

	if len(notImplemented) > 0 {
		return nil, fmt.Errorf("workflow contains not implemented features: %s", strings.Join(notImplemented, ","))
	}

	return wf, nil
}

func CheckErrors(wt *parser.WorkflowTemplate) error {
	if len(wt.Errors) == 0 {
		return nil
	}
	return NewWorkflowParseError(wt.Errors)
}

func toParserPermissionPolicy(permissionsPolicy types.DefaultWorkflowPermissions) (parser.PermissionsPolicy, error) {
	switch permissionsPolicy {
	case types.LimitedReadWorkflowPermissions:
		return parser.PermissionsPolicyLimitedRead, nil
	case types.WriteWorkflowPermissions:
		return parser.PermissionsPolicyWrite, nil
	default:
		return parser.PermissionsPolicyLimitedRead, fmt.Errorf("unknown permissions policy: %s", permissionsPolicy)
	}
}
