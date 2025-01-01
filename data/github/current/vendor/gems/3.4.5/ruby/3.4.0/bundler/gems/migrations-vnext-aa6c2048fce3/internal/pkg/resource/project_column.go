package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type projectColumn struct {
	baseHandler
	pb                      *v1.ProjectColumn
	importedProjectColumnID int64
}

var _ handler = (*projectColumn)(nil)

func newProjectColumn(pb *v1.ProjectColumn, logger log.Logger) *projectColumn {
	return &projectColumn{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (pc *projectColumn) resourceID() string {
	return pc.pb.ResourceId
}

func (pc *projectColumn) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(pc.pb.ProjectResourceId)
	for _, workflow := range pc.pb.Workflows {
		deps.strDeps.Add(workflow.CreatorResourceId)
		if workflow.LastUpdaterResourceId != "" {
			deps.strDeps.Add(workflow.LastUpdaterResourceId)
		}
		for _, action := range workflow.Actions {
			deps.strDeps.Add(action.CreatorResourceId)
			if action.LastUpdaterResourceId != "" {
				deps.strDeps.Add(action.LastUpdaterResourceId)
			}
		}
	}
	return deps, nil
}

func (pc *projectColumn) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	var columnPurpose octov1.ColumnPurpose
	switch pc.pb.Purpose {
	case "todo":
		columnPurpose = octov1.ColumnPurpose_COLUMN_PURPOSE_TODO
	case "in_progress":
		columnPurpose = octov1.ColumnPurpose_COLUMN_PURPOSE_IN_PROGRESS
	case "done":
		columnPurpose = octov1.ColumnPurpose_COLUMN_PURPOSE_DONE
	default:
		columnPurpose = octov1.ColumnPurpose_COLUMN_PURPOSE_INVALID
	}

	workflows := make([]*octov1.ProjectWorkflow, 0, len(pc.pb.Workflows))
	for _, workflow := range pc.pb.Workflows {
		var triggerType octov1.TriggerType
		switch workflow.TriggerType {
		case "issue_closed":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_ISSUE_CLOSED_TRIGGER
		case "issue_pending_card_added":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_ISSUE_PENDING_CARD_ADDED_TRIGGER
		case "issue_reopened":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_ISSUE_REOPENED_TRIGGER
		case "pr_approved":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_PR_APPROVED_TRIGGER
		case "pr_closed_not_merged":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_PR_CLOSED_NOT_MERGED_TRIGGER
		case "pr_merged":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_PR_MERGED_TRIGGER
		case "pr_pending_approval":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_PR_PENDING_APPROVAL_TRIGGER
		case "pr_pending_card_added":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_PR_PENDING_CARD_ADDED_TRIGGER
		case "pr_reopened":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_PR_REOPENED_TRIGGER
		case "review_dismissed":
			triggerType = octov1.TriggerType_TRIGGER_TYPE_REVIEW_DISMISSED_TRIGGER
		default:
			triggerType = octov1.TriggerType_TRIGGER_TYPE_INVALID
		}

		actions := make([]*octov1.ProjectWorkflowAction, 0, len(workflow.Actions))
		for _, action := range workflow.Actions {
			pwa := &octov1.ProjectWorkflowAction{
				CreatorLogin: resolved[action.CreatorResourceId].strVal,
				CreatedAt:    action.CreatedAt,
				UpdatedAt:    action.UpdatedAt,
			}
			if action.LastUpdaterResourceId != "" {
				pwa.LastUpdaterLogin = resolved[action.LastUpdaterResourceId].strVal
			}
			actions = append(actions, pwa)
		}

		pw := &octov1.ProjectWorkflow{
			CreatorLogin: resolved[workflow.CreatorResourceId].strVal,
			TriggerType:  triggerType,
			CreatedAt:    workflow.CreatedAt,
			UpdatedAt:    workflow.UpdatedAt,
			Actions:      actions,
		}
		if workflow.LastUpdaterResourceId != "" {
			pw.LastUpdaterLogin = resolved[workflow.LastUpdaterResourceId].strVal
		}
		workflows = append(workflows, pw)
	}

	req := &octov1.ImportProjectColumnRequest{
		ImportedProjectId: resolved[pc.pb.ProjectResourceId].int64Val,
		Name:              pc.pb.Name,
		Color:             pc.pb.Color,
		CreatedAt:         pc.pb.CreatedAt,
		UpdatedAt:         pc.pb.UpdatedAt,
		Purpose:           columnPurpose,
		Position:          pc.pb.Position,
		HiddenAt:          pc.pb.HiddenAt,
		Workflows:         workflows,
	}

	res, err := importer.ImportProjectColumn(ctx, req)
	if err != nil {
		pc.logger.WithError(err).Error("failed to import project column", kvp.Any("request", req))
		return fmt.Errorf("failed to load project column: %w", err)
	}
	if res.ProjectColumnImportErrors != nil {
		for _, importErr := range res.ProjectColumnImportErrors {
			pc.logger.Error("errors importing project column",
				kvp.String("error_message", importErr.ErrorMessage),
				kvp.String("model_type", importErr.ModelType.String()),
			)
		}
	}
	pc.importedProjectColumnID = res.ImportedProjectColumnId

	return nil
}

func (pc *projectColumn) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		pc.resourceID(): &transformedValues{
			int64Val: pc.importedProjectColumnID,
		},
	}
}
