package ghapi

import (
	"context"
	"strings"
	"time"

	"github.com/github/turboscan/ts"
	gogh "github.com/google/go-github/v52/github"
	"github.com/pkg/errors"
)

type WorkflowRunAnnotations struct {
	WorkflowRunID        ts.WorkflowRunEID
	RepositoryID         ts.RepositoryEID
	CheckSuiteID         int64
	CheckSuiteStatus     string
	CheckSuiteConclusion string
	CheckSuiteCreatedAt  time.Time
	CheckSuiteUpdatedAt  time.Time
	CheckRuns            []CheckRun
}

type CheckRun struct {
	ID          int64
	Name        string
	Status      string
	Conclusion  string
	StartedAt   time.Time
	CompletedAt time.Time
	Annotations []Annotation
}

type Annotation struct {
	Path            string
	Title           string
	Message         string
	AnnotationLevel string
}

var ErrMissingRequiredField = errors.New("The GitHub API response is missing a required field")
var ErrWorkflowRunNotCompleted = errors.New("The workflow run has not finished yet")

type WorkflowRunAnnotationsGetter interface {
	GetWorkflowRunAnnotations(context.Context, ts.OwnerEID, ts.RepositoryEID, ts.WorkflowRunEID) (*WorkflowRunAnnotations, error)
}

func validateRepoInputs(r *gogh.Repository) error {
	var missingFields []string
	if r.Name == nil {
		missingFields = append(missingFields, "repo.name")
	}
	if r.Owner == nil {
		missingFields = append(missingFields, "repo.owner")
	} else if r.Owner.Login == nil {
		missingFields = append(missingFields, "repo.owner_login")
	}
	if len(missingFields) > 0 {
		return errors.Wrapf(ErrMissingRequiredField, "missing fields %s", strings.Join(missingFields, ", "))
	}
	return nil
}

func validateWorkflowRun(r *gogh.WorkflowRun) error {
	// Validate status
	if r.Status == nil {
		return errors.Wrapf(ErrMissingRequiredField, "missing field workflow_run.status")
	}
	if *r.Status != "completed" {
		return ErrWorkflowRunNotCompleted
	}

	var missingFields []string
	if r.CheckSuiteID == nil {
		missingFields = append(missingFields, "workflow_run.check_suite_id")
	}
	if r.Conclusion == nil {
		missingFields = append(missingFields, "workflow_run.conclusion")
	}
	if r.CreatedAt == nil {
		missingFields = append(missingFields, "workflow_run.created_at")
	}
	if r.UpdatedAt == nil {
		missingFields = append(missingFields, "workflow_run.updated_at")
	}
	if len(missingFields) > 0 {
		return errors.Wrapf(ErrMissingRequiredField, "missing fields %s", strings.Join(missingFields, ", "))
	}
	return nil
}

func validateCheckrun(r *gogh.CheckRun) error {
	var missingFields []string
	if r.ID == nil {
		missingFields = append(missingFields, "checkrun.id")
	}
	if r.StartedAt == nil {
		missingFields = append(missingFields, "checkrun.started_at")
	}
	if r.Name == nil {
		missingFields = append(missingFields, "checkrun.name")
	}
	if r.Status == nil {
		missingFields = append(missingFields, "checkrun.status")
	}
	if r.Conclusion == nil {
		missingFields = append(missingFields, "checkrun.conclusion")
	}
	if r.CompletedAt == nil {
		missingFields = append(missingFields, "checkrun.completed_at")
	}
	if len(missingFields) > 0 {
		return errors.Wrapf(ErrMissingRequiredField, "missing fields %s", strings.Join(missingFields, ", "))
	}
	return nil
}

func validateCheckrunAnnotation(a *gogh.CheckRunAnnotation) error {
	var missingFields []string
	if a.Path == nil {
		missingFields = append(missingFields, "checkrun.path")
	}
	if a.Message == nil {
		missingFields = append(missingFields, "checkrun.message")
	}
	if a.Title == nil {
		missingFields = append(missingFields, "checkrun.title")
	}
	if a.AnnotationLevel == nil {
		missingFields = append(missingFields, "checkrun.annotation_level")
	}
	if len(missingFields) > 0 {
		return errors.Wrapf(ErrMissingRequiredField, "missing fields %s", strings.Join(missingFields, ", "))
	}
	return nil

}

// GetWorkflowRunAnnotations returns the annotations for a workflow run using the public REST API.
// Annotations are associated with CheckRuns, so we need to fetch the entire tree: WorkflowRun -> CheckSuite -> []CheckRun -> []Annotations
func GetWorkflowRunAnnotations(ctx context.Context, c *gogh.Client, repoID ts.RepositoryEID, wrID ts.WorkflowRunEID) (*WorkflowRunAnnotations, error) {
	out := &WorkflowRunAnnotations{
		WorkflowRunID: wrID,
		RepositoryID:  repoID,
	}

	// WARNING: This might be incorrect in the context of Proxima!
	repo, _, err := c.Repositories.GetByID(ctx, int64(repoID))
	if err != nil {
		return nil, errors.Wrapf(err, "failed to fetch repo information with ID: %d", repoID)
	}
	err = validateRepoInputs(repo)
	if err != nil {
		return nil, err
	}
	repoName := *repo.Name
	repoOwnerLogin := *repo.Owner.Login

	wr, _, err := c.Actions.GetWorkflowRunByID(ctx, repoOwnerLogin, repoName, int64(wrID))
	if err != nil {
		return nil, err
	}
	err = validateWorkflowRun(wr)
	if err != nil {
		return nil, err
	}
	out.CheckSuiteID = *wr.CheckSuiteID
	out.CheckSuiteConclusion = *wr.Conclusion
	out.CheckSuiteCreatedAt = wr.CreatedAt.Time
	out.CheckSuiteUpdatedAt = wr.UpdatedAt.Time
	out.CheckSuiteStatus = *wr.Status

	checkRuns, _, err := c.Checks.ListCheckRunsCheckSuite(ctx, repoOwnerLogin, repoName, out.CheckSuiteID, nil)
	if err != nil {
		return out, err
	}
	if len(checkRuns.CheckRuns) == 0 {
		return out, errors.Wrap(ErrMissingRequiredField, "missing fields checkruns.checkruns")
	}

	crs := make([]CheckRun, 0, len(checkRuns.CheckRuns))
	for _, checkRun := range checkRuns.CheckRuns {
		err := validateCheckrun(checkRun)
		if err != nil {
			return out, err
		}
		cr := CheckRun{
			ID:          *checkRun.ID,
			Status:      *checkRun.Status,
			Conclusion:  *checkRun.Conclusion,
			Name:        *checkRun.Name,
			StartedAt:   checkRun.StartedAt.Time,
			CompletedAt: checkRun.CompletedAt.Time,
		}

		annotations, _, err := c.Checks.ListCheckRunAnnotations(ctx, repoOwnerLogin, repoName, cr.ID, nil)
		if err != nil {
			return out, err
		}
		cr.Annotations = make([]Annotation, 0, len(annotations))
		for _, annotation := range annotations {
			err := validateCheckrunAnnotation(annotation)
			if err != nil {
				return out, err
			}
			cr.Annotations = append(cr.Annotations, Annotation{
				Path:            *annotation.Path,
				Title:           *annotation.Title,
				Message:         *annotation.Message,
				AnnotationLevel: *annotation.AnnotationLevel,
			})
		}
		crs = append(crs, cr)
	}
	out.CheckRuns = crs
	return out, nil
}

func (c *Client) GetWorkflowRunAnnotations(ctx context.Context, ownerID ts.OwnerEID, repoID ts.RepositoryEID, wrID ts.WorkflowRunEID) (*WorkflowRunAnnotations, error) {
	authC, err := newClientForRepo(ctx, c.appClient, ownerID, repoID)
	if err != nil {
		return nil, errors.Wrap(err, "creating authenticated GitHub client")
	}
	return GetWorkflowRunAnnotations(ctx, authC, repoID, wrID)
}
