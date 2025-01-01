package jobs

import (
	"context"
	"fmt"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/managedanalyses"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
)

type RunCodeqlOnPullRequest struct {
	RepoID         ts.RepositoryEID
	OwnerID        ts.OwnerEID
	Sha            ts.Sha
	ActorGRID      ts.ActorGRID
	ActorLogin     string
	PRNumber       uint32
	EventTimestamp *sqltime.Time
}

var _ aqueduct.EnqueableJob = (*RunCodeqlOnPullRequest)(nil)

func (r RunCodeqlOnPullRequest) GetRepositoryID() *ts.RepositoryEID {
	return &r.RepoID
}

func (r RunCodeqlOnPullRequest) Name() string {
	return "RunCodeqlOnPullRequest"
}

func (r RunCodeqlOnPullRequest) Queue() string {
	return "turboscan-run-codeql-on-pull-request"
}

func (r RunCodeqlOnPullRequest) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}

func (r RunCodeqlOnPullRequest) actor() *ts.ActorGRIDLogin {
	return &ts.ActorGRIDLogin{
		GRID:  r.ActorGRID,
		Login: r.ActorLogin,
	}
}

func (r RunCodeqlOnPullRequest) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	ctx = appctx.WithKVPs(ctx, r.Sha)
	if s == nil || s.ManagedAnalyses == nil {
		return errors.New("missing required services")
	}
	return r.perform(ctx, s.ManagedAnalyses)
}

func (r RunCodeqlOnPullRequest) perform(ctx context.Context, ma *maservice.ManagedAnalyses) error {
	if ma.LaunchApiClient == nil {
		appctx.Logger(ctx).Error("Actions is not configured.")
		return nil
	}

	config, _, codeqlPacks, err := ma.RequireRunnableCodeqlConfig(ctx, r.RepoID)
	if err != nil {
		switch {
		case errors.Is(err, ts.ErrCodeqlRepoNotFound):
			appctx.Logger(ctx).Info("Managed analyses disabled for repository")
			return nil
		case errors.Is(err, ts.ErrNotOnboarded):
			appctx.Logger(ctx).Info("Managed analyses is not enabled for this repository")
			return nil
		case errors.Is(err, maservice.ErrRequiredServicesNotEnabled):
			appctx.Logger(ctx).Info("Required services are not enabled")
			return nil
		case errors.Is(err, ts.ErrMissingActionsInstallationID):
			appctx.Logger(ctx).Info("Missing Actions Installation ID")
			return nil
		default:
			return err
		}
	}

	// Construct the ref from the pull request number
	ref := ts.Ref(fmt.Sprintf("refs/pull/%d/head", r.PRNumber))
	run, err := config.NewRun(r.actor(), ref, r.Sha, ts.CodeqlRunTriggeringEvent_PULL_REQUEST, false, r.OwnerID, codeqlPacks, r.EventTimestamp)
	if err != nil {
		return errors.Wrap(err, "failed to build new run")
	}

	exists, err := ma.DataService.PreviousRunExists(ctx, run.RepositoryID, run.Sha)
	if err != nil {
		return errors.Wrap(err, "failed to check if previous run exists")
	}
	if exists && !flipper.HasCodeScanningRerunCommitAnalysis(ctx, r.OwnerID, r.RepoID) {
		appctx.Logger(ctx).Info("Codeql workflow already triggered, codeql_run records found in db")
		return nil
	}

	err = ma.LaunchApiClient.RunDynamicWorkflow(ctx, run)
	if err != nil {
		appctx.Logger(ctx).Error("failed to submit dynamic workflow")
		if errors.Is(err, ts.ErrSpammyUser) {
			// no need to retry this failure
			return nil
		}
		return errors.Wrap(err, "failed to submit dynamic workflow")
	}
	managedanalyses.DynamicWorkflowRunLogAndStats(ctx, config, run)

	err = ma.DataService.CreateCodeqlRun(ctx, run)
	if err != nil {
		// We do not return this error since everything else should still work and we do not want to retry the job
		// and spend customer's Actions minutes on a rerun.
		appctx.Logger(ctx).Info("failed to create an entry for ts_codeql_run after submitting dynamic workflow")
		return nil
	}

	err = CancelObsoleteRuns(ctx, ma, run)
	if err != nil {
		// We do not return this error since everything else should still work and we do not want to retry the job
		// and spend customer's Actions minutes on a rerun.
		appctx.Logger(ctx).Info("failed to cancel workflow runs", kvp.String("gh.turboscan.error", err.Error()))
		return nil
	}

	return nil
}
