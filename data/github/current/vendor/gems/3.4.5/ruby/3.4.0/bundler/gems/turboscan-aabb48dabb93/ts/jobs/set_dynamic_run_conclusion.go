package jobs

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/flipper"
	managedanalyses "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
)

// SetDynamicRunConclusion is called once we know that a Dynamic Run has reached a final state (success/failure).
// The job is then responsible for updating all entries that depended on this run.
type SetDynamicRunConclusion struct {
	RepositoryID  ts.RepositoryEID
	OwnerID       ts.OwnerEID
	WorkflowRunID ts.WorkflowRunEID
	Sha           ts.Sha
	Conclusion    ts.CodeqlRunStatus
}

var _ aqueduct.EnqueableJob = (*SetDynamicRunConclusion)(nil)

func (s SetDynamicRunConclusion) GetRepositoryID() *ts.RepositoryEID {
	return &s.RepositoryID
}

func (s SetDynamicRunConclusion) Name() string {
	return "SetDynamicRunConclusion"
}

func (s SetDynamicRunConclusion) Queue() string {
	return "turboscan-set-dynamic-run-conclusion"
}

func (s SetDynamicRunConclusion) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}

func (s SetDynamicRunConclusion) Perform(ctx context.Context, services *aqueduct.TSServices) error {
	ctx = appctx.With(ctx, s.WorkflowRunID.AsKVP())
	if services == nil || services.ManagedAnalyses == nil || services.Aqueduct == nil {
		return errors.New("missing required services")
	}
	return s.perform(ctx, services.ManagedAnalyses, services.GetDeliveriesByWorkflowRunID, services.Aqueduct, services.IsEnterpriseEnv)
}

func (s SetDynamicRunConclusion) perform(ctx context.Context, ma *managedanalyses.ManagedAnalyses, getDeliveriesByWorkflowRunID func(ctx context.Context, repoID ts.RepositoryEID, workflowRunID ts.WorkflowRunEID) ([]ts.Delivery, error), aqueduct aqueduct.JobPerformer, isEnterpriseEnv bool) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	appctx.Logger(ctx).Info("Progress checking")

	run, err := ma.UpsertCodeqlRunStatus(ctx, s.RepositoryID, s.WorkflowRunID, s.Sha, s.Conclusion)
	if err != nil {
		switch {
		case errors.Is(err, ts.ErrCodeqlRepoNotFound):
			appctx.Logger(ctx).Error("CodeqlRepo not found")
		case errors.Is(err, ts.ErrCodeqlConfigNotFound):
			appctx.Logger(ctx).Error("CodeqlConfig not found")
		case errors.Is(err, ts.ErrCodeqlRunNotFound):
			appctx.Logger(ctx).Error("CodeqlRun not found")
		case errors.Is(err, ts.ErrWorkflowRunAlreadyCompleted):
			appctx.Logger(ctx).Info("Validation run already completed")
		default:
			// Unknown error - retry
			return err
		}
		return nil
	}

	doPublishAnnotations := run.Validation() || flipper.HasEmitRunAnnotationsForSteadyState(ctx, s.OwnerID, s.RepositoryID)
	if isEnterpriseEnv {
		// Never publish on GHES
		doPublishAnnotations = false
	}

	if doPublishAnnotations {
		// Fetch Annotations from the validation run
		job := &PublishWorkflowRunAnnotations{
			RepoID:        s.RepositoryID,
			OwnerID:       s.OwnerID,
			WorkflowRunID: s.WorkflowRunID,
			SkipWarehouse: !run.Validation(), // Only send validation annotations to the warehouse to avoid noise.
		}
		// We are adding a delay on this job to avoid a race condition with the annotations data.
		jobid, err := aqueduct.PerformLaterAt(ctx, job, time.Now().Add(10*time.Second))
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("Failed to enqueue PublishWorkflowRunAnnotations")
		} else {
			appctx.Logger(ctx).Info("Enqueued PublishWorkflowRunAnnotations", kvp.String("gh.aqueduct.job.id", jobid))
		}
	}

	if flipper.HasSkipRunStatsReporting(ctx, s.OwnerID, s.RepositoryID) {
		return nil
	}

	deliveries, err := getDeliveriesByWorkflowRunID(ctx, s.RepositoryID, s.WorkflowRunID)

	if err != nil {
		appctx.Report(ctx, err, nil)
		appctx.Logger(ctx).WithError(err).Error("Failed to fetch Workflow Deliveries")
	}

	emitRunTelemetry(ctx, run, deliveries)

	return nil
}

func emitRunTelemetry(ctx context.Context, run *ts.CodeqlRun, deliveries []ts.Delivery) {
	if !run.Status.IsFinal() {
		appctx.Logger(ctx).Info("CodeQL run is not completed yet. Skipping telemetry.", kvp.Uint64("codeqlRunID", uint64(run.ID)))
		return
	}

	runType := "steady"
	if run.Validation() {
		runType = "validation"
	}

	tv := "unknown"
	if run.Config != nil {
		tv = run.Config.TemplateVersion
	}

	status := "success"
	if run.Failed() {
		status = "failure"
	}

	event := run.TriggeringEvent.String()

	tags := stats.Tags{
		"run_type":                  runType,
		"triggering_event":          event,
		"workflow_template_version": tv,
		"jit_validation":            fmt.Sprint(run.JITValidation()),
		"status":                    status,
		"labelled_runner":           fmt.Sprint(run.Config.RunnerLabel != ""),
	}

	appctx.Stats(ctx).Counter("default_setup.completed_run", tags, 1)

	if run.EventTimestamp != nil {
		labelledRunners := strconv.FormatBool(run.Config.RunnerLabel != "")

		for _, d := range deliveries {
			duration := d.CreatedAt.Time.Sub(run.EventTimestamp.Time)

			appctx.Stats(ctx).DistributionMs("default_setup.trigger_to_analysis_uploaded", stats.Tags{
				"triggering_event": event,
				"status":           status,
				"language":         d.Environment["language"],
				"labelled_runners": labelledRunners,
			}, duration)
		}

		triggerToCompletion := time.Since(run.EventTimestamp.Time)
		appctx.Stats(ctx).DistributionMs("default_setup.trigger_to_run_completion", stats.Tags{
			"triggering_event": event,
			"status":           status,
			"labelled_runners": labelledRunners,
		}, triggerToCompletion)

		// Also log outliers
		if triggerToCompletion > 24*time.Hour {
			appctx.Logger(ctx).Info("Run completed after more than 1 day", kvp.Duration("duration", triggerToCompletion), run.RepositoryID.AsKVP(), run.ID.AsKVP(),
				kvp.Int("gh.turboscan.delivery_count", len(deliveries)), kvp.String("gh.turboscan.triggering_event", event), kvp.String("status", status))
		}
	}
}
