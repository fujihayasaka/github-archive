package healbuilds

import (
	"context"
	"errors"
	"strconv"
	"time"

	errs "github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"

	"github.com/github/go-kvp"

	"github.com/github/launch/constants"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/buildhealer"
	"github.com/github/launch/workflowbuild/azp/azperrors"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/build"
)

type healer interface {
	CompleteBuild(ctx context.Context, w buildhealer.WorkflowInfo, status, conclusion string, reason buildhealer.HealReason) (fixType string, healed bool, err error)
}

//gocyclo:ignore
func (r *Runner) healWorkflow(ctx context.Context, w buildhealer.WorkflowInfo, h healer, postbackGracePeriod time.Duration) bool {
	var healingReason string
	ctx = ctxstash.WithFields(ctx,
		kvp.Int64("gh.launch.workflow.id", w.ID),
		kvp.String("gh.launch.workflow.execution.id", w.UUID.String()),
		kvp.String("gh.repo.global_id", w.RepositoryID.String()),
		kvp.String("gh.check_suite.global_id", w.CheckSuiteID.String()),
		kvp.Int64("gh.launch.workflow.state", int64(w.State)),
		kvp.String("gh.launch.workflow.state_description", w.State.String()),
	)

	// Log database ids as well to make StaffTools searches easier.
	if !w.RepositoryID.IsZeroValue() {
		if _, dbid, err := w.RepositoryID.Decode(); err != nil {
			r.obs.Error(ctx, "error decoding repository global id", kvp.Err(err))
		} else {
			ctx = ctxstash.WithFields(ctx, kvp.Int64("gh.repo.id", dbid))
		}
	}

	if !w.CheckSuiteID.IsZeroValue() {
		if _, dbid, err := w.CheckSuiteID.Decode(); err != nil {
			r.obs.Error(ctx, "error decoding check suite global id", kvp.Err(err))
		} else {
			ctx = ctxstash.WithFields(ctx, kvp.Int64("gh.check_suite.id", dbid))
		}
	}

	var workflowAgeDays int64
	if w.CreatedAt != nil {
		workflowAgeDays = int64(time.Since(*w.CreatedAt) / (24 * time.Hour))
		ctx = ctxstash.WithFields(ctx,
			kvp.Time("gh.launch.workflow.created_at", *w.CreatedAt),
			kvp.Int64("gh.launch.workflow.age_days", workflowAgeDays),
		)
	} else {
		workflowAgeDays = -1
	}

	// check cache to see if we should ignore
	skipCache := r.cacheClient.SkipWorkflowExecutionIDFor(w.ExecutionID)
	skipReason, ok, err := skipCache.Get(ctx)
	if err != nil {
		r.obs.Error(ctx, "error getting healing cache", kvp.Err(err))
	} else if ok {
		r.obs.Log(ctx, "skipped workflow healing because it is cached as skippable", kvp.String("gh.launch.workflow_healing_skip_reason", skipReason))
		r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": skipReason, "skipping": "true"}, 1)
		return false
	}

	// Make a Service client for this repo
	sc, err := r.serviceClientFactory.ClientFromRepoGID(ctx, w.RepositoryID)
	if err != nil {
		if _, azpResxNotFound := errs.Cause(err).(*deployer.GetAzpResourcesError); azpResxNotFound {
			// Attempt to heal by marking workflow as Canceled
			status := azptypes.StatusCompleted
			conclusion := azptypes.ResultCanceled

			fixType, _, err := h.CompleteBuild(ctx, w, status, conclusion, buildhealer.ReasonScheduled)

			fields := []kvp.Field{
				kvp.String("gh.repo.global_id", w.RepositoryID.String()),
				kvp.String("gh.launch.workflow_healing.fix_type", fixType),
			}

			if err != nil {
				fields = append(fields, kvp.Err(err))
				r.obs.Error(ctx, "error healing build", fields...)
				r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "heal_error"}, 1)
				return false
			}

			healingReason = "repo_deleted"
			r.obs.Log(ctx, "healed workflow in launch", kvp.String("gh.launch.workflow_healing_reason", healingReason))
			r.obs.Counter(ctx, "healing.workflows_healed", statter.Tags{"reason": healingReason, "workflow_age_days": strconv.FormatInt(workflowAgeDays, 10)}, 1)
			return true
		}

		r.obs.Error(ctx, "error creating service client for repository", kvp.Err(err))
		r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "error"}, 1)
		return false
	}

	// Load the current state from Actions Service
	// We do this even if the runState is None, as queuing a run sometimes works even on error or request timeout.
	ri, err := sc.RunInfo(ctx, w.UUID)
	if err != nil {
		r.obs.Error(ctx, "error fetching run info", kvp.Err(err))

		// If azp returned Run Not Found we still proceed with healing.
		azpErr := azperrors.GetAZPError(err)
		if azpErr == nil || azpErr.ExceptionType != azperrors.RunNotFoundException {
			r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "error"}, 1)
			return false
		}
	}

	var status, conclusion string
	if ri != nil {
		fields := []kvp.Field{
			kvp.String("gh.check_run.status", ri.Status),
			kvp.String("gh.launch.run.conclusion", ri.Conclusion),
			kvp.Bool("gh.launch.has_pendings_gate", ri.HasPendingGate),
			kvp.Bool("gh.launch.is_waiting_on_resource", ri.IsWaitingOnResource),
		}

		if ri.StartedAt != nil {
			fields = append(fields, kvp.Time("gh.launch.started_at", *ri.StartedAt))
		}
		if ri.CompletedAt != nil {
			fields = append(fields, kvp.Time("gh.launch.completed_at", *ri.CompletedAt))
		}

		r.obs.Log(ctx, "runinfo response", fields...)

		if ri.HasPendingGate {
			r.obs.Log(ctx, "skipped workflow healing because it has pending gate")
			r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "has_pending_gate"}, 1)
			err := skipCache.Set(ctx, "has_pending_gate", calculateSkipTime(time.Now(), ri.StartedAt))
			if err != nil {
				r.obs.Error(ctx, "error setting skip cache", kvp.Err(err))
			} else {
				r.obs.Debug(ctx, "cached as skippable")
			}
			return false
		}
		if ri.IsWaitingOnResource {
			r.obs.Log(ctx, "skipped workflow healing because it is currently waiting on a group permit")
			r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "is_waiting_on_resource"}, 1)
			err := skipCache.Set(ctx, "is_waiting_on_resource", calculateSkipTime(time.Now(), ri.StartedAt))
			if err != nil {
				r.obs.Error(ctx, "error setting skip cache", kvp.Err(err))
			} else {
				r.obs.Debug(ctx, "cached as skippable")
			}

			return false
		}

		switch ri.Status {
		case azptypes.StatusInProgress, azptypes.StatusThrottled:
			// A nil StartedAt indicates that the run is still queued
			if ri.StartedAt == nil {
				if w.CreatedAt != nil && time.Since(*w.CreatedAt) > queuedRunGracePeriod {
					r.obs.Log(ctx, "cancelling queued run because it has been queued for too long")
					cancelRun(ctx, r.obs, sc, w.ExternalBuildID, "error cancelling queued run", "queued_too_long")
				}

				r.obs.Log(ctx, "skipped workflow healing because it is currently queued")
				r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "status_queued"}, 1)
				return false
			} else if w.CreatedAt != nil && time.Since(*w.CreatedAt) > constants.WorkflowMaxRunTime {
				r.obs.Log(ctx, "cancelling run because it is too old")
				cancelRun(ctx, r.obs, sc, w.ExternalBuildID, "error cancelling old run", "too_old")
			}

			r.obs.Log(ctx, "skipped workflow healing because it is currently in progress")
			r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "status_in_progress"}, 1)
			err := skipCache.Set(ctx, "status_in_progress", calculateSkipTime(time.Now(), ri.StartedAt))
			if err != nil {
				r.obs.Error(ctx, "error setting skip cache", kvp.Err(err))
			} else {
				r.obs.Debug(ctx, "cached as skippable")
			}
			return false

		case azptypes.StatusCompleted:
			if ri.CompletedAt == nil {
				r.obs.Report(ctx, errors.New("completed workflow run missing completed_at time"))
				r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "unknown_completion_time"}, 1)
				return false
			}

			timeSinceCompletion := time.Since(*ri.CompletedAt)
			ctx = ctxstash.WithFields(ctx, kvp.Float("gh.launch.since_completion_minutes", timeSinceCompletion.Minutes()))

			if timeSinceCompletion < postbackGracePeriod {
				// The run completed somewhat recently, and we're giving status postbacks a chance to be delivered and processed before we
				// resort to healing. Healing a run can result in steps, artifacts and logs not being persisted in dotcom.
				r.obs.Log(ctx, "skipped workflow healing during postback grace period")
				r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "postback_grace_period"}, 1)
				return false
			}

			r.obs.Statter.LegacyTiming(ctx, "run_completion_delay", statter.Tags{"within_threshold": "false", "workflow_healed": "true"}, timeSinceCompletion)
			healingReason = "run_completed"

		default:
			r.obs.Report(ctx, errors.New("workflow run status not recognized"), kvp.String("gh.launch.workflow_run.status", ri.Status))
			r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "status_not_recognized"}, 1)
			return false
		}

		status = ri.Status
		conclusion = ri.Conclusion
	} else if w.State == build.WorkflowStateNone {
		// The azp run not being found is consistent with the workflow state.
		r.obs.Log(ctx, "Run not queued.")
		healingReason = "run_not_queued"

		status = azptypes.StatusCompleted
		conclusion = azptypes.ResultCanceled
	} else {
		// Queued or started run not found on the azp side.
		r.obs.Error(ctx, "Queued run not found. Inspect check suite.")
		healingReason = "run_not_found"

		status = azptypes.StatusCompleted
		conclusion = azptypes.ResultCanceled
	}

	// Attempt to heal with the info we have
	fixType, healed, err := h.CompleteBuild(ctx, w, status, conclusion, buildhealer.ReasonScheduled)
	if err != nil {
		r.obs.Error(ctx, "error healing build", kvp.Err(err))
		r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": "heal_error"}, 1)
		return false
	}

	if !healed {
		// Dotcom changes either weren't necessary or possible.
		// We track these as not healed because the healing job didn't improve the customer experience.
		// The build was marked complete in the Launch database to avoid reprocessing.
		r.obs.Log(ctx, "completed build without healing")
		r.obs.Counter(ctx, "healing.workflows_not_healed", statter.Tags{"reason": fixType, "completed_in_launch": "true"}, 1)
		return false
	}

	if healingReason == "" {
		healingReason = "unknown"
	}
	r.obs.Log(ctx, "healed workflow in dotcom", kvp.String("gh.launch.workflow_healing_reason", healingReason))
	r.obs.Counter(ctx, "healing.workflows_healed", statter.Tags{"reason": healingReason, "workflow_age_days": strconv.FormatInt(workflowAgeDays, 10)}, 1)
	return true
}

const (
	defaultWaitTime = 30 * time.Minute
)

var (
	skipTimeScalingFactor = 24 / DefaultMaxHealableJobAge.Hours()
)

func calculateSkipTime(now time.Time, startTime *time.Time) time.Duration {
	// If the run hasn't been started, wait at least 30 minutes before hitting Actions Service again.
	if startTime == nil {
		return defaultWaitTime
	}
	runAge := now.Sub(*startTime)

	// run age is older than 24h, run it more frequently if it's young and less
	// frequently if its older (young jobs are more likely to need healing)

	runIn := time.Duration(runAge.Seconds()*skipTimeScalingFactor) * time.Second

	// we want to check each workflow at least once per day
	if runIn > 24*time.Hour {
		return 24 * time.Hour
	}
	// we want to check each workflow at most every `defaultWaitTime`
	if runIn < defaultWaitTime {
		return defaultWaitTime
	}
	return runIn
}

func cancelRun(ctx context.Context, obs *observability.Observability, repoClient azp.RepositoryClient, externalID, errorMessage, tag string) {
	if externalID == "" {
		obs.Error(ctx, "cannot cancel run with empty external ID")
		return
	}

	err := repoClient.Cancel(ctx, externalID, nil)
	if err != nil {
		obs.Error(ctx, errorMessage, kvp.Err(err))
	} else {
		obs.Counter(ctx, "healing.workflows_canceled", statter.Tags{"reason": tag}, 1)
	}
}
