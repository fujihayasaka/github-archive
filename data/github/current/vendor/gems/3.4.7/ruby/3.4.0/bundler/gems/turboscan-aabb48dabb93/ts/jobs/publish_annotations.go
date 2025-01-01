package jobs

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/github/go-stats"
	v0 "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/ghapi"
	managedanalyses "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// PublishWorkflowRunAnnotations is a job that publishes run annotations for a
// failed workflow run to Hydro
type PublishWorkflowRunAnnotations struct {
	RepoID        ts.RepositoryEID
	OwnerID       ts.OwnerEID
	WorkflowRunID ts.WorkflowRunEID
	SkipWarehouse bool
}

func (p PublishWorkflowRunAnnotations) GetRepositoryID() *ts.RepositoryEID {
	return &p.RepoID
}

var _ aqueduct.EnqueableJob = (*PublishWorkflowRunAnnotations)(nil)

func (p PublishWorkflowRunAnnotations) Name() string {
	return "PublishWorkflowRunAnnotations"
}

func (p PublishWorkflowRunAnnotations) Queue() string {
	return "turboscan-publish-workflow-run-annotations"
}

func (p PublishWorkflowRunAnnotations) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}

func (p PublishWorkflowRunAnnotations) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	ctx = appctx.WithKVPs(ctx, p.WorkflowRunID)
	if s == nil || s.ManagedAnalyses == nil {
		return errors.New("missing required services")
	}

	err := p.perform(ctx, s.ManagedAnalyses.GitHubApiClient, s.ManagedAnalyses.HydroPublisher)
	// This is low priority job, just used for telemetry
	// It has low volume, and the api with gh/gh is a bit finicky
	// so we just want to log the errors and not return them
	result := "success"

	if err != nil {
		if isSkippable(err) {
			appctx.Logger(ctx).WithError(err).Error("Skipped publishing annotations due to skippable error")
			result = "skipped"
		} else {
			appctx.Logger(ctx).WithError(err).Error("Failed to publish annotations")
			result = "error"
		}
	}

	appctx.Stats(ctx).Counter("default_setup.publish_annotations", stats.Tags{"result": result}, 1)

	return nil
}

func (p PublishWorkflowRunAnnotations) perform(ctx context.Context, api ghapi.WorkflowRunAnnotationsGetter, hydro managedanalyses.ManagedAnalysesHydroPublisher) error {
	data, err := api.GetWorkflowRunAnnotations(ctx, p.OwnerID, p.RepoID, p.WorkflowRunID)
	if err != nil {
		return errors.Wrap(err, "failed to get workflow run annotations")
	}

	j, _ := json.Marshal(data)
	appctx.Logger(ctx).Info(string(j))

	if p.SkipWarehouse {
		// These annotations are useful for debugging various situations,
		// but in the datawarehouse we want to keep only a subset of this data
		// mostly around validation runs.
		return nil
	}
	hydroMessages := serializeAnnotations(data)
	return hydro.WorkflowRunAnnotationsBatch(ctx, hydroMessages)
}

func serializeAnnotations(annotations *ghapi.WorkflowRunAnnotations) []*v0.WorkflowRunAnnotation {
	hydroMessages := make([]*v0.WorkflowRunAnnotation, 0)
	for _, cr := range annotations.CheckRuns {
		for _, annotation := range cr.Annotations {
			message := &v0.WorkflowRunAnnotation{
				RepositoryId:         int64(annotations.RepositoryID),
				WorkflowRunId:        int64(annotations.WorkflowRunID),
				CheckSuiteId:         annotations.CheckSuiteID,
				CheckSuiteStatus:     annotations.CheckSuiteStatus,
				CheckSuiteConclusion: annotations.CheckSuiteConclusion,
				CheckSuiteCreatedAt:  timestamppb.New(annotations.CheckSuiteCreatedAt),
				CheckSuiteUpdatedAt:  timestamppb.New(annotations.CheckSuiteUpdatedAt),
				CheckRunId:           cr.ID,
				CheckRunName:         cr.Name,
				CheckRunStatus:       cr.Status,
				CheckRunConclusion:   cr.Conclusion,
				CheckRunStartedAt:    timestamppb.New(cr.StartedAt),
				CheckRunCompletedAt:  timestamppb.New(cr.CompletedAt),
				Path:                 annotation.Path,
				Title:                annotation.Title,
				Message:              annotation.Message,
				AnnotationLevel:      annotation.AnnotationLevel,
			}
			hydroMessages = append(hydroMessages, message)
		}
	}

	return hydroMessages
}

func isSkippable(err error) bool {
	if strings.Contains(err.Error(), "your IP address is not permitted to access this resource") {
		return true
	}
	if strings.Contains(err.Error(), "There is at least one repository that does not exist") {
		return true
	}
	return false
}
