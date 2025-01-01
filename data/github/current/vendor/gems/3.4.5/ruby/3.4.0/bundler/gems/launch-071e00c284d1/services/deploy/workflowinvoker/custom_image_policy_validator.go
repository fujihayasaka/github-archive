package workflowinvoker

import (
	"context"

	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/workflowparser"
)

// Fail workflows that contain a snapshot step if custom image generation is disabled.
func (i *buildInvoker) IsCustomImageGenerationAllowedByPolicy(ctx context.Context, errCtx *WorkflowStartErrorContext, parsedWorkflow *workflowparser.Workflow) *WorkflowStartErr {
	// Check the feature flag to see if the policy is being enforced
	if !i.data.WorkflowFeatureFlags.CustomImagesPolicyEnforced {
		return nil
	}
	// Only error if there's a snapshot step
	if !hasSnapshotStep(parsedWorkflow, parsedWorkflow.CalledWorkflows) {
		return nil
	}

	// The feature is not available in GHES
	if i.isEnterprise {
		userErr := terrors.NewUserError("`snapshot` is not supported.")
		return NewPermanentWorkflowStartError(errCtx, userErr, customImageGenErrType)
	}

	// Make sure non-org-owned repos don't sneak through since they won't have the policy set
	if i.data.Owner.Type != ownerTypeOrganisation {
		userErr := terrors.NewUserError("`snapshot` is not supported for personal repositories.")
		return NewPermanentWorkflowStartError(errCtx, userErr, customImageGenErrType)
	}

	// If the owner has custom images disabled, the run should fail
	if !i.data.HasHostedRunnerCustomImagesEnabled {
		userErr := terrors.NewUserError("The workflow contains `snapshot` but the organization is not allowed to create custom images.")
		return NewPermanentWorkflowStartError(errCtx, userErr, customImageGenErrType)
	}

	return nil
}

func hasSnapshotStep(w *workflowparser.Workflow, c map[string]workflowparser.CalledWorkflow) bool {
	for _, job := range w.Parsed().Jobs {
		if job.Snapshot != nil {
			return true
		}
	}
	for _, calledWorkflow := range c {
		for _, job := range calledWorkflow.Workflow.Parsed().Jobs {
			if job.Snapshot != nil {
				return true
			}
		}
	}
	return false
}
