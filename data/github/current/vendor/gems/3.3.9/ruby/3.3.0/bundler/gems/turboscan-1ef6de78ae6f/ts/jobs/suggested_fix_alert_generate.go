package jobs

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	ccf "github.com/github/turboscan/ts/cocofix"
	"github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"

	"github.com/pkg/errors"
)

type SuggestedFixAlertGenerate struct {
	RepoID              ts.RepositoryEID
	CommitOid           ts.Sha
	PullRequestID       ts.PullRequestEID
	ToolName            string
	ToolVersion         string
	UserID              uint64
	SuggestedFixAlertID ts.SuggestedFixAlertID
}

func PerformSuggestedFixAlertGenerate(ctx context.Context, s *aqueduct.TSServices, p SuggestedFixAlertGenerate, workload ts.ThrottlerWorkload) error {
	ctx = appctx.With(ctx,
		p.CommitOid.AsKVP(),
		kvp.Any("gh.commit.sha", p.CommitOid),
		kvp.String("gh.tool.name", p.ToolName),
		kvp.String("gh.tool.version", p.ToolVersion),
		kvp.Uint64("gh.user.id", p.UserID),
		kvp.Uint64("gh.turboscan.suggested_fix_alert_id", uint64(p.SuggestedFixAlertID)),
		kvp.Uint8("gh.turboscan.retry_count", appctx.GetAqueductJobRetryCount(ctx)),
		p.PullRequestID.AsKVP(),
		p.RepoID.AsKVP(),
	)
	ctx = appctx.WithLogger(ctx, appctx.Logger(ctx).Named("generate_suggested_fixes_job"))

	appctx.Logger(ctx).Info("Generating suggested fix alert")

	if s == nil || s.SuggestedFixes == nil || s.Aqueduct == nil {
		return errors.New("missing required services")
	}
	// publishState is true when we need to publish the state change of the alert. It is false
	// when we are retrying the job.
	publishState := true
	err := p.perform(ctx, s.SuggestedFixes, workload)

	if err != nil {
		var te *ccf.TransientError
		transient := "false"
		if errors.As(err, &te) {
			transient = "true"
		}

		retryCount := appctx.GetAqueductJobRetryCount(ctx)
		if retryCount < aqueduct.MaxRetryCount {
			appctx.Logger(ctx).WithError(err).Info("Generating suggested fix alert",
				p.RepoID.AsKVP(),
				p.CommitOid.AsKVP(),
				p.SuggestedFixAlertID.AsKVP())
			appctx.Stats(ctx).Counter(workload.ProcessedMetric(), stats.Tags{"workload": workload.String(), "transient": transient, "error": "true"}, 1)
			// This will retry so we do not want to publish the state change
			publishState = false
		} else {
			payload := map[string]string{
				"repository_id":          fmt.Sprintf("%d", p.RepoID),
				"commit_oid":             p.CommitOid.String(),
				"suggested_fix_alert_id": fmt.Sprintf("%d", p.SuggestedFixAlertID),
			}
			appctx.Report(ctx, errors.Wrap(err, "job retry limit exceeded"), payload)
			appctx.Stats(ctx).Counter(workload.ProcessedMetric(), stats.Tags{"workload": workload.String(), "transient": transient, "error": "true", "noretry": "true"}, 1)

			sfa, err := s.SuggestedFixes.GetSuggestedFixAlert(ctx, p.SuggestedFixAlertID, nil)

			if err != nil {
				err = errors.Wrap(err, "failed to load the SFA from the DB")
			} else {
				// There will be no more retries, so we must mark the sfa as error
				err = s.SuggestedFixes.UpdateSFAState(ctx, sfa, ts.SuggestedFixAlertStateError, nil, nil)
				if err != nil {
					err = errors.Wrap(err, "failed to mark the SFA as error when giving up on retries")
				}
			}

			if err != nil {
				appctx.Report(ctx, err, nil)
			} else {
				appctx.Stats(ctx).DistributionMs(workload.StateChangeDurationMetric(), stats.Tags{
					"workload":     workload.String(),
					"state":        string(ts.SuggestedFixAlertStateError),
					"state_before": string(sfa.State),
					"transient":    transient,
					"error":        "true",
					"noretry":      "true",
				}, time.Since(sfa.CreatedAt.Time))
			}
		}
	}

	// Publish the state change if needed
	if publishState {
		p.publishStateChange(ctx, s.Aqueduct, s.SuggestedFixes)
	}

	return err
}

func (p SuggestedFixAlertGenerate) perform(ctx context.Context, sf *suggestedfixes.SuggestedFixes, workload ts.ThrottlerWorkload) error {
	err := sf.GenerateSuggestedFix(ctx, p.SuggestedFixAlertID, p.CommitOid, ts.ToToolName(p.ToolName), p.ToolVersion, p.UserID, workload)
	if err != nil {
		return errors.Wrap(err, "failed to generate a suggested fix")
	}

	return nil
}

// publishStateChange will update the Elasticsearch index and publish the state change to dotcom.
// Note: there is no errors returned from this as no errors here are considered fatal.
func (p SuggestedFixAlertGenerate) publishStateChange(ctx context.Context,
	jobPerformer aqueduct.JobPerformer, sf *suggestedfixes.SuggestedFixes) {

	// DV: the SuggestedFixStateChanged could be done in the service just after updating the SFA
	payload := map[string]string{
		"repository_id":          fmt.Sprintf("%d", p.RepoID),
		"commit_oid":             p.CommitOid.String(),
		"pull_request_id":        fmt.Sprintf("%d", p.PullRequestID),
		"suggested_fix_alert_id": fmt.Sprintf("%d", p.SuggestedFixAlertID),
	}
	sfa, err := sf.GetSuggestedFixAlert(ctx, p.SuggestedFixAlertID, nil)
	if err != nil {
		appctx.Report(ctx, errors.Wrap(err, "Failed to get the SFA for publishing the state changed"), payload)
		return // Return because there is nothing else we can do without the alert number.
	}
	err = sf.GitHubTwirpApiClient.SuggestedFixStateChanged(ctx, p.RepoID, p.PullRequestID, []uint32{sfa.LogicalAlertNumber})
	if err != nil {
		appctx.Report(ctx, errors.Wrap(err, "Failed to call internal Monolith Twirp service"), payload)
	}

	// Index the alerts that got an updated suggested fix
	indexJob := &AlertIndexing{
		Context:             "suggested-fix-alert-generate",
		RepositoryID:        p.RepoID,
		LogicalAlertNumbers: []uint32{sfa.LogicalAlertNumber},
	}
	_, err = jobPerformer.PerformLater(ctx, indexJob)
	if err != nil {
		appctx.Report(ctx, errors.Wrap(err, "Failed to enqueue indexing job"), payload)
	}
}
